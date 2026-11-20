//
// RecoveryCoachModel.swift
// Tempo
//
// The Recovery Coach screen's brain: finds the session that needs attention,
// gathers weigh-ins (Apple Health from the Withings scale + manual entries) and
// fluids, asks the server for the numbers, and keeps the last answer so the
// screen still works with no network. All sweat/recovery math is server-side.
//

import CoreLocation
import Foundation
import Observation
import OSLog

// MARK: - API seam

protocol RecoveryCoachAPI: Sendable {
    func recentSessions() async throws -> [CoachSession]
    func recovery(_ request: CoachRecoveryRequest) async throws -> CoachRecoveryResponse
}

struct LiveRecoveryCoachAPI: RecoveryCoachAPI {
    let apiClient: APIClient

    func recentSessions() async throws -> [CoachSession] {
        try await apiClient.request(.coachRecentSessions())
    }

    func recovery(_ request: CoachRecoveryRequest) async throws -> CoachRecoveryResponse {
        try await apiClient.request(.coachRecovery(), body: request)
    }
}

// MARK: - Model

@MainActor
@Observable
final class RecoveryCoachModel {
    enum Step: Int, CaseIterable {
        case sessions, health, coach

        var title: String {
            switch self {
            case .sessions: "Finding your session"
            case .health: "Reading your weigh-ins from Health"
            case .coach: "Working out your numbers"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case loading(Step)
        /// Nothing usable and nothing cached.
        case failed(String)
    }

    // What the screen shows.
    private(set) var phase: Phase = .idle
    private(set) var sessions: [CoachSession] = []
    private(set) var session: CoachSession?
    private(set) var result: CoachRecoveryResponse?
    /// When `result` was computed; set when it came from the phone's memory.
    private(set) var resultDate: Date?
    /// The server could not be reached, so `result` is the last one we have.
    private(set) var isOfflineResult = false
    private(set) var weighIns: [CoachWeighIn] = []
    private(set) var healthNote: String?
    private(set) var fluids = CoachFluidBreakdown(loggedMl: 0, quickAnswerLiters: nil, editedLiters: nil)
    private(set) var loadStartedAt: Date?

    var bottleMl: Int { store.read().bottleMl }

    private let api: any RecoveryCoachAPI
    private let healthKit: (any HealthKitServiceProtocol)?
    private let store: RecoveryCoachStore
    private let waterMl: (Date, Date) -> Int
    private let location: (any LocationFixProviding)?
    private let now: () -> Date
    private let logger = Logger(subsystem: "app.tempo", category: "recovery-coach")
    private var generation = 0

    init(
        api: any RecoveryCoachAPI,
        healthKit: (any HealthKitServiceProtocol)?,
        store: RecoveryCoachStore = .shared,
        waterMl: @escaping (Date, Date) -> Int = { _, _ in 0 },
        location: (any LocationFixProviding)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.healthKit = healthKit
        self.store = store
        self.waterMl = waterMl
        self.location = location
        self.now = now
        adoptStoredState(requestedID: nil)
    }

    /// A session needs attention or has a result worth showing.
    var hasSession: Bool { session != nil }

    var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    // MARK: - Loading

    /// Foreground, push tap, pull-to-refresh. `requestedID` = the session a push named.
    func refresh(requestedID: String? = nil) async {
        generation += 1
        let mine = generation
        loadStartedAt = now()
        adoptStoredState(requestedID: requestedID)
        phase = .loading(.sessions)
        do {
            let fetched = try await api.recentSessions()
            guard mine == generation else { return }
            store.update { $0.sessions = fetched; $0.sessionsFetchedAt = Date() }
            adoptStoredState(requestedID: requestedID)
        } catch {
            guard mine == generation else { return }
            if Task.isCancelled {
                phase = .idle
                return
            }
            logger.error("recent sessions failed: \(error.localizedDescription, privacy: .public)")
            // Keep what we have; the card/screen still works from the phone's memory.
            if session == nil {
                phase = .failed(Self.message(for: error))
                return
            }
        }
        guard session != nil else {
            phase = .idle
            return
        }
        await compute(generationToken: mine)
    }

    /// Re-ask the server for the current session (after a weigh-in or fluid change).
    func recompute() async {
        generation += 1
        loadStartedAt = now()
        await compute(generationToken: generation)
    }

    private func adoptStoredState(requestedID: String?) {
        let state = store.read()
        sessions = state.sessions
        let current = now()
        var pick = RecoverySessionPicker.focus(sessions: state.sessions, now: current) {
            state.results[$0]?.response.status == .ready
        }
        if let requestedID, let wanted = state.sessions.first(where: { $0.id == requestedID }) {
            pick = wanted
        }
        if pick?.id != session?.id {
            result = nil
            resultDate = nil
            isOfflineResult = false
        }
        session = pick
        if let pick, let cached = state.results[pick.id] {
            result = cached.response
            resultDate = cached.storedAt
        }
    }

    private func compute(generationToken mine: Int) async {
        guard let session else { return }
        let state = store.read()

        phase = .loading(.health)
        var health: [HealthWeightSample] = []
        healthNote = nil
        if let healthKit {
            let window = RecoveryWeighIns.window(start: session.start, end: session.end)
            do {
                health = try await healthKit.fetchBodyMassSamples(from: window.from, to: window.to)
            } catch {
                logger.error("body mass read failed: \(error.localizedDescription, privacy: .public)")
                healthNote = "Couldn't read Apple Health. You can enter your weight by hand."
            }
        }
        guard mine == generation else { return }

        let sent = RecoveryWeighIns.select(health: health, manual: state.manualWeighIns, start: session.start, end: session.end)
        weighIns = sent
        let postTime = sent.last(where: { $0.time >= session.end.addingTimeInterval(-600) })?.time ?? now()
        fluids = CoachFluidBreakdown(
            loggedMl: waterMl(session.start.addingTimeInterval(-15 * 60), postTime),
            quickAnswerLiters: state.quickAnswers[session.id]?.liters,
            editedLiters: state.fluidEdits[session.id]
        )

        var lat: Double?
        var lon: Double?
        if let fix = await location?.fixIfAuthorized(timeout: 3) {
            lat = RecoveryCoachFormat.coarse(fix.coordinate.latitude)
            lon = RecoveryCoachFormat.coarse(fix.coordinate.longitude)
        }
        guard mine == generation else { return }

        // Body mass sizes the food targets when there is no weigh-in yet: the newest weight in Health.
        var bodyMass = sent.last?.kg
        if bodyMass == nil, let healthKit {
            do {
                bodyMass = try await healthKit.fetchBodyComposition().weightKg
            } catch {
                logger.error("body composition read failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard mine == generation else { return }

        phase = .loading(.coach)
        let request = CoachRecoveryRequest(
            sessionId: session.id, sessionStart: session.start, weighIns: sent, drankLiters: fluids.liters,
            latitude: lat, longitude: lon, bodyMassKg: bodyMass
        )
        do {
            let response = try await api.recovery(request)
            guard mine == generation else { return }
            let stored = now()
            store.update { $0.results[session.id] = CoachCachedResult(response: response, storedAt: stored) }
            result = response
            resultDate = stored
            isOfflineResult = false
            phase = .idle
        } catch {
            // A cancelled request is not "offline": the next refresh will redo it.
            guard mine == generation else { return }
            if Task.isCancelled {
                phase = .idle
                return
            }
            logger.error("recovery failed: \(error.localizedDescription, privacy: .public)")
            if result != nil {
                isOfflineResult = true
                phase = .idle
            } else {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    static func message(for error: Error) -> String {
        if let api = error as? APIError, let text = api.errorDescription, !text.isEmpty { return text }
        return "Couldn't reach Tempo. Check your connection and try again."
    }

    // MARK: - Edits

    func addManualWeighIn(kg: Double, at time: Date) async {
        store.addManualWeighIn(CoachWeighIn(time: time, kg: kg, source: CoachWeighIn.sourceManual), now: now())
        await recompute()
    }

    func answerFluid(_ action: CoachQuickAnswerAction) async {
        guard let session else { return }
        store.recordQuickAnswer(sessionID: session.id, bottles: action.bottles, now: now())
        store.update { $0.fluidEdits[session.id] = nil }
        await recompute()
    }

    /// nil clears the typed amount.
    func editFluid(liters: Double?) async {
        guard let session else { return }
        store.update { $0.fluidEdits[session.id] = liters }
        await recompute()
    }

    func setBottleMl(_ ml: Int) {
        store.update { $0.bottleMl = min(max(ml, 200), 2000) }
    }

    // MARK: - Derived text

    /// The single thing to do next, with its reason. nil when the plan is ready.
    var startHere: (title: String, reason: String)? {
        guard let result, let session else { return nil }
        switch result.status {
        case .ready:
            return nil
        case .implausible:
            return ("Weigh yourself again", "The two weights don't look right together. Step on the scale again, in the same clothes.")
        case .needsWeighIn:
            if result.missingPost {
                return (
                    "Weigh yourself now",
                    "Your \(session.label.lowercased()) ended \(Self.ago(session.end, now: now())). Before you drink, step on the scale so I can see what you sweated out."
                )
            }
            return (
                "Add your weight from before",
                "I need one weight from the 3 hours before the session. Enter it if you remember it."
            )
        }
    }

    static func ago(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 2 { return "just now" }
        if minutes < 90 { return "\(minutes) min ago" }
        return "\(minutes / 60) h ago"
    }
}
