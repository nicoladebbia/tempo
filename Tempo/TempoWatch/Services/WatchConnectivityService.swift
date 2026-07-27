//
// WatchConnectivityService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import WatchConnectivity

// MARK: - WatchConnectivityService

// Per APPLE_WATCH_APP.md Section 5 — WCSession management on Watch.
// Per XCODE_PROJECT_STRUCTURE.md Section 11.4

@Observable
final class WatchConnectivityService: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityService()

    var latestSnapshot: WatchSnapshot = .placeholder
    /// §21 — today's real workout queue pushed by the phone (application
    /// context, so it survives the watch app being closed). nil until the
    /// phone has synced once.
    var latestWorkout: WatchWorkoutPayload?
    var isReachable: Bool = false

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

    func sendAction(_ action: WatchQuickAction, payload: [String: String] = [:]) {
        let actionPayload = WatchActionPayload(action: action, payload: payload)
        guard let data = try? JSONEncoder().encode(actionPayload),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(dict)
        }
    }
}

// MARK: WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
        // Load latest context on activation
        let context = session.receivedApplicationContext
        if let snapshot = WatchSnapshot.from(dictionary: context) {
            DispatchQueue.main.async {
                self.latestSnapshot = snapshot
            }
        }
        ingestWorkout(from: context)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let snapshot = WatchSnapshot.from(dictionary: message) {
            DispatchQueue.main.async {
                self.latestSnapshot = snapshot
            }
        }
        ingestWorkout(from: message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let snapshot = WatchSnapshot.from(dictionary: applicationContext) {
            DispatchQueue.main.async {
                self.latestSnapshot = snapshot
            }
        }
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
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
}
