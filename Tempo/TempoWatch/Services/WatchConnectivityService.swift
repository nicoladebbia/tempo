//
// WatchConnectivityService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import WatchConnectivity

// MARK: - WatchActionAckState

/// Result of a `sendAction` round-trip. Drives which haptic the caller
/// plays — a success haptic must never fire before the phone actually
/// confirms the action (§22).
enum WatchActionAckState {
    /// The phone was reachable and confirmed it applied the action.
    case confirmed
    /// Sent (or queued while unreachable) but not confirmed applied —
    /// honest "it's on its way, not verified yet" state.
    case queued
    /// The phone was reachable and confirmed it could NOT apply the action.
    case failed
}

// MARK: - WatchConnectivityService

@Observable
final class WatchConnectivityService: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityService()

    /// Honest default: no fake achievement numbers until the phone syncs.
    /// Restored from the last real snapshot on disk (if any) so a relaunch
    /// doesn't flash back to the empty state while WCSession reactivates.
    var latestSnapshot: WatchSnapshot = WatchConnectivityService.loadPersistedSnapshot() ?? .empty
    /// §21 — today's real workout queue pushed by the phone (application
    /// context, so it survives the watch app being closed). nil until the
    /// phone has synced once.
    var latestWorkout: WatchWorkoutPayload?
    var isReachable: Bool = false

    private static let snapshotDefaultsKey = "tempo.watch.lastSnapshot"

    override private init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else {
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send a quick action to the phone. `onAck` reports whether the phone
    /// actually confirmed it (via the message reply handler) — callers must
    /// gate their success haptic on `.confirmed`, not on the tap itself.
    func sendAction(
        _ action: WatchQuickAction,
        payload: [String: String] = [:],
        onAck: (@Sendable (WatchActionAckState) -> Void)? = nil
    ) {
        let actionPayload = WatchActionPayload(action: action, payload: payload)
        guard let data = try? JSONEncoder().encode(actionPayload),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            onAck?(.failed)
            return
        }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: { reply in
                let confirmed = (reply["success"] as? Bool) ?? false
                DispatchQueue.main.async {
                    onAck?(confirmed ? .confirmed : .queued)
                }
            }, errorHandler: { _ in
                DispatchQueue.main.async {
                    onAck?(.queued)
                }
            })
        } else {
            WCSession.default.transferUserInfo(dict)
            DispatchQueue.main.async {
                onAck?(.queued)
            }
        }
    }

    // MARK: - Persistence

    /// Persist every real (non-empty) snapshot so a relaunch shows the last
    /// known-real data instead of the honest-empty placeholder while
    /// WCSession reactivates and re-syncs.
    private func persist(_ snapshot: WatchSnapshot) {
        guard snapshot.hasRealData,
              let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.snapshotDefaultsKey)
    }

    private static func loadPersistedSnapshot() -> WatchSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    private func ingestSnapshot(from dict: [String: Any]) {
        guard let snapshot = WatchSnapshot.from(dictionary: dict) else {
            return
        }
        DispatchQueue.main.async {
            self.latestSnapshot = snapshot
            self.persist(snapshot)
        }
    }
}

// MARK: WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isReachable = reachable
        }
        // Load latest context on activation
        let context = session.receivedApplicationContext
        ingestSnapshot(from: context)
        ingestWorkout(from: context)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ingestSnapshot(from: message)
        ingestWorkout(from: message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingestSnapshot(from: applicationContext)
        ingestWorkout(from: applicationContext)
    }

    /// §21 — pull the workout payload out of any incoming dictionary. Keyed
    /// under its own context key so it coexists with the snapshot fields.
    private func ingestWorkout(from dict: [String: Any]) {
        guard let raw = dict[WatchWorkoutPayload.contextKey] as? [String: Any],
              let payload = WatchWorkoutPayload.from(dictionary: raw)
        else {
            return
        }
        DispatchQueue.main.async {
            // Latest-wins: ignore an out-of-order older context.
            if let current = self.latestWorkout, current.updatedAt > payload.updatedAt {
                return
            }
            self.latestWorkout = payload
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isReachable = reachable
        }
    }
}
