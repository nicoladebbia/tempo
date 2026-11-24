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

// MARK: - RecoveryCoachAPI

protocol RecoveryCoachAPI: Sendable {
    func recentSessions() async throws -> [CoachSession]
    func recovery(_ request: CoachRecoveryRequest) async throws -> CoachRecoveryResponse
}

// MARK: - LiveRecoveryCoachAPI

struct LiveRecoveryCoachAPI: RecoveryCoachAPI {
    let apiClient: APIClient

    func recentSessions() async throws -> [CoachSession] {
        try await apiClient.request(.coachRecentSessions())
    }

    func recovery(_ request: CoachRecoveryRequest) async throws -> CoachRecoveryResponse {
        try await apiClient.request(.coachRecovery(), body: request)
    }
}

// MARK: - RecoveryCoachModel

@MainActor
@Observable
final class RecoveryCoachModel {
    enum Step: Int, CaseIterable {
        case sessions
        case health
        case coach

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

    var bottleMl: Int {
        store.read().bottleMl
    }

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
    var hasSession: Bool {
        session != nil
    }

    /// The last fetch got "the server has no WHOOP access yet". Cleared by a successful fetch;
    /// the app refreshes again as soon as the phone shares its WHOOP access.
    private(set) var awaitingWhoopAccess = false
    /// Bumped by `whoopAccessShared()`. A fetch that 404s after a share landed mid-flight
    /// (the 404 and the share can arrive in either order) asks once more.
    private var whoopShares = 0

    /// The phone just shared WHOOP access with the server.
    func whoopAccessShared() async {
        whoopShares += 1
        guard awaitingWhoopAccess else {
            return
        }
        await refresh()
    }

    var isLoading: Bool {
        if case .loading = phase {
            return true
        }
        return false
    }

    // MARK: - Loading

    /// Foreground, push tap, pull-to-refresh. `requestedID` = the session a push named.
    func refresh(requestedID: String? = nil) async {
        await refresh(requestedID: requestedID, retryAfterShare: true)
    }

    private func refresh(requestedID: String?, retryAfterShare: Bool) async {
        generation += 1
        let sharesAtStart = whoopShares
        let mine = generation
        loadStartedAt = now()
        adoptStoredState(requestedID: requestedID)
        phase = .loading(.sessions)
        do {
            let fetched = try await api.recentSessions()
            guard mine == generation else {
                return
            }
            awaitingWhoopAccess = false
            store.update { $0.sessions = fetched; $0.sessionsFetchedAt = Date() }
            adoptStoredState(requestedID: requestedID)
        } catch APIError.notFound {
            // The server has no WHOOP access yet (the phone shares it after its WHOOP check) or it ran out.
            // Not an error for the user: there is simply nothing new to weigh until the next share.
            guard mine == generation else {
                return
            }
            if retryAfterShare, whoopShares != sharesAtStart {
                // A share landed while this fetch was out: the 404 may predate it.
                await refresh(requestedID: requestedID, retryAfterShare: false)
                return
            }
            awaitingWhoopAccess = true
            logger.info("recent sessions: server has no WHOOP access yet")
            if session == nil {
                phase = .idle
                return
            }
        } catch {
            guard mine == generation else {
                return
            }
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
        guard let session else {
            return
        }
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
        guard mine == generation else {
            return
        }

        let sent = RecoveryWeighIns.select(health: health, manual: state.manualWeighIns, start: session.start, end: session.end)
        weighIns = sent
        let water = RecoveryWeighIns.waterWindow(weighIns: sent, start: session.start, end: session.end, now: now())
        fluids = CoachFluidBreakdown(
            loggedMl: waterMl(water.from, water.to),
            // Priced at today's bottle size, so changing the size also re-prices an earlier answer.
            quickAnswerLiters: state.quickAnswers[session.id].map { $0.bottles * Double(state.bottleMl) / 1000 },
            editedLiters: state.fluidEdits[session.id]
        )

        var lat: Double?
        var lon: Double?
        if let fix = await location?.fixIfAuthorized(timeout: 3) {
            lat = RecoveryCoachFormat.coarse(fix.coordinate.latitude)
            lon = RecoveryCoachFormat.coarse(fix.coordinate.longitude)
        }
        guard mine == generation else {
            return
        }

        // Body mass sizes the food targets when there is no weigh-in yet: the newest weight in Health.
        var bodyMass = sent.last?.kg
        if bodyMass == nil, let healthKit {
            do {
                bodyMass = try await healthKit.fetchBodyComposition().weightKg
                    .flatMap { RecoveryWeighIns.plausibleKg.contains($0) ? $0 : nil }
            } catch {
                logger.error("body composition read failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard mine == generation else {
            return
        }

        phase = .loading(.coach)
        let request = CoachRecoveryRequest(
            sessionId: session.id, sessionStart: session.start, weighIns: sent, drankLiters: fluids.liters,
            latitude: lat, longitude: lon, bodyMassKg: bodyMass
        )
        do {
            let response = try await api.recovery(request)
            guard mine == generation else {
                return
            }
            let stored = now()
            store.update { $0.results[session.id] = CoachCachedResult(response: response, storedAt: stored) }
            result = response
            resultDate = stored
            isOfflineResult = false
            phase = .idle
        } catch {
            // A cancelled request is not "offline": the next refresh will redo it.
            guard mine == generation else {
                return
            }
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
        if let api = error as? APIError, let text = api.errorDescription, !text.isEmpty {
            return text
        }
        return "Couldn't reach Tempo. Check your connection and try again."
    }

    // MARK: - Edits

    func addManualWeighIn(kg: Double, at time: Date) async {
        store.addManualWeighIn(CoachWeighIn(time: time, kg: kg, source: CoachWeighIn.sourceManual), now: now())
        await recompute()
    }

    func removeManualWeighIn(at time: Date) async {
        store.removeManualWeighIn(at: time)
        await recompute()
    }

    /// The hand-entered weight stored at `time` (to the second), if any. Read before
    /// adding one, so an Undo can put back what a new weight replaced.
    func manualWeighIn(at time: Date) -> CoachWeighIn? {
        store.read().manualWeighIns.first { Int($0.time.timeIntervalSince1970) == Int(time.timeIntervalSince1970) }
    }

    /// Takes back `addManualWeighIn(kg:at:)`: removes it and restores the weight
    /// it replaced at the same second, if there was one.
    func undoManualWeighIn(at time: Date, restoring previous: CoachWeighIn?) async {
        store.removeManualWeighIn(at: time)
        if let previous {
            store.addManualWeighIn(previous, now: now())
        }
        await recompute()
    }

    func answerFluid(_ action: CoachQuickAnswerAction) async {
        guard let session else {
            return
        }
        store.recordQuickAnswer(sessionID: session.id, bottles: action.bottles, now: now())
        store.update { $0.fluidEdits[session.id] = nil }
        await recompute()
    }

    /// Forgets the typed amount AND the quick answer for this session.
    func clearFluid() async {
        guard let session else {
            return
        }
        store.update { state in
            state.fluidEdits[session.id] = nil
            state.quickAnswers[session.id] = nil
        }
        await recompute()
    }

    /// Sets the typed amount.
    func editFluid(liters: Double?) async {
        guard let session else {
            return
        }
        store.update { $0.fluidEdits[session.id] = liters }
        await recompute()
    }

    func setBottleMl(_ ml: Int) {
        store.update { $0.bottleMl = min(max(ml, 200), 2000) }
    }

    // MARK: - Derived text

    /// The single thing to do next, with its reason. nil when the plan is ready.
    var startHere: (title: String, reason: String)? {
        guard let result, let session else {
            return nil
        }
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
        if minutes < 2 {
            return "just now"
        }
        if minutes < 90 {
            return "\(minutes) min ago"
        }
        return "\(minutes / 60) h ago"
    }
}
