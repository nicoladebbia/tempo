//
// RecoveryCoachStore.swift
// Tempo
//
// Everything the Recovery Coach remembers on the phone, in one small Codable
// blob in UserDefaults (NOT SwiftData: no schema change, and the notification
// buttons can write to it while the app is in the background with no network):
// manual weigh-ins, the quick "how much did you drink" answer per session,
// edited fluid amounts, the bottle size, the pre-match reminder toggle, the
// last server result per session (so the screen works offline) and the last
// session list.
//

import Foundation
import os

struct CoachQuickAnswer: Codable, Equatable, Sendable {
    /// 0, 0.5, 1 or 2.
    let bottles: Double
    /// Bottle size at the moment of the answer, in ml.
    let bottleMl: Int
    let answeredAt: Date

    var liters: Double { bottles * Double(bottleMl) / 1000 }
}

struct CoachCachedResult: Codable, Equatable, Sendable {
    let response: CoachRecoveryResponse
    let storedAt: Date
}

struct RecoveryCoachState: Codable, Equatable, Sendable {
    static let defaultBottleMl = 750

    var manualWeighIns: [CoachWeighIn] = []
    var quickAnswers: [String: CoachQuickAnswer] = [:]
    /// Litres the user typed in by hand for a session; replaces every other source.
    var fluidEdits: [String: Double] = [:]
    var bottleMl = defaultBottleMl
    var preMatchReminderOn = true
    var results: [String: CoachCachedResult] = [:]
    var sessions: [CoachSession] = []
    var sessionsFetchedAt: Date?
}

/// Thread-safe (a notification button runs off the main actor).
final class RecoveryCoachStore: @unchecked Sendable {
    static let shared = RecoveryCoachStore()
    /// Anything older than this is dropped on write.
    static let keepFor: TimeInterval = 14 * 24 * 3600

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, key: String = "tempo.recoveryCoach.state.v1") {
        self.defaults = defaults
        self.key = key
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func read() -> RecoveryCoachState {
        lock.withLock { load() }
    }

    /// Read, change, prune, write: one step under the lock.
    @discardableResult
    func update(now: Date = Date(), _ change: (inout RecoveryCoachState) -> Void) -> RecoveryCoachState {
        lock.withLock {
            var state = load()
            change(&state)
            Self.prune(&state, now: now)
            do {
                defaults.set(try Self.encoder().encode(state), forKey: key)
            } catch {
                logger.error("coach state not saved: \(error.localizedDescription, privacy: .public)")
            }
            return state
        }
    }

    private let logger = Logger(subsystem: "app.tempo", category: "recovery-coach-store")

    private func load() -> RecoveryCoachState {
        guard let data = defaults.data(forKey: key) else { return RecoveryCoachState() }
        do {
            return try Self.decoder().decode(RecoveryCoachState.self, from: data)
        } catch {
            // Keep the unreadable blob so nothing is lost for good, then start empty.
            logger.error("coach state unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            defaults.set(data, forKey: key + ".unreadable")
            return RecoveryCoachState()
        }
    }

    static func prune(_ state: inout RecoveryCoachState, now: Date) {
        let cutoff = now.addingTimeInterval(-keepFor)
        state.manualWeighIns.removeAll { $0.time < cutoff }
        state.quickAnswers = state.quickAnswers.filter { $0.value.answeredAt >= cutoff }
        state.results = state.results.filter { $0.value.storedAt >= cutoff }
        let live = Set(state.quickAnswers.keys).union(state.results.keys)
        state.fluidEdits = state.fluidEdits.filter { live.contains($0.key) }
    }

    // MARK: - Convenience writes

    func recordQuickAnswer(sessionID: String, bottles: Double, now: Date = Date()) {
        update(now: now) { state in
            state.quickAnswers[sessionID] = CoachQuickAnswer(bottles: bottles, bottleMl: state.bottleMl, answeredAt: now)
        }
    }

    func addManualWeighIn(_ weighIn: CoachWeighIn, now: Date = Date()) {
        update(now: now) { state in
            state.manualWeighIns.removeAll { Int($0.time.timeIntervalSince1970) == Int(weighIn.time.timeIntervalSince1970) }
            state.manualWeighIns.append(weighIn)
        }
    }

    func removeManualWeighIn(at time: Date) {
        update { state in
            state.manualWeighIns.removeAll { Int($0.time.timeIntervalSince1970) == Int(time.timeIntervalSince1970) }
        }
    }
}
