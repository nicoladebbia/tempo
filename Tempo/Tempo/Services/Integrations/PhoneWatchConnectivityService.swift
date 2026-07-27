//
// PhoneWatchConnectivityService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import WatchConnectivity

// MARK: - Phone Watch Connectivity Service (iPhone Side)

// Per XCODE_PROJECT_STRUCTURE.md Section 11.5 — WCSession management on iPhone.

final class PhoneWatchConnectivityService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchConnectivityService()

    /// §21 — set by the Training surface; receives decoded watch actions on
    /// the main actor. Actions arriving earlier buffer in `pendingActions`.
    private var quickActionHandler: (@MainActor (WatchActionPayload) -> Void)?
    private var pendingActions: [WatchActionPayload] = []

    func activate() {
        guard WCSession.isSupported() else {
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pushSnapshot(_ snapshot: [String: Any]) {
        guard WCSession.default.activationState == .activated else {
            return
        }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(snapshot, replyHandler: nil)
        } else {
            try? WCSession.default.updateApplicationContext(snapshot)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncoming(userInfo)
    }
}

// MARK: - §21 real sync

extension PhoneWatchConnectivityService {
    /// Push today's real workout to the watch via application context (the
    /// always-latest channel — WCSession delivers the newest context even
    /// when the watch app is closed). Other context keys are preserved.
    func pushWorkout(_ payload: WatchWorkoutPayload) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled
        else {
            return
        }
        var context = WCSession.default.applicationContext
        context[WatchWorkoutPayload.contextKey] = payload.toDictionary()
        try? WCSession.default.updateApplicationContext(context)
    }

    /// Route a decoded watch quick action to whoever registered (the Training
    /// surface). Actions arriving before a handler exists (queued userInfo
    /// delivered at launch) buffer and replay on registration — nothing the
    /// watch logged is dropped.
    func setQuickActionHandler(_ handler: @escaping @MainActor (WatchActionPayload) -> Void) {
        DispatchQueue.main.async {
            self.quickActionHandler = handler
            let pending = self.pendingActions
            self.pendingActions = []
            for action in pending {
                handler(action)
            }
        }
    }

    private func handleIncoming(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let action = try? JSONDecoder().decode(WatchActionPayload.self, from: data)
        else {
            return
        }
        DispatchQueue.main.async {
            if let handler = self.quickActionHandler {
                handler(action)
            } else {
                self.pendingActions.append(action)
            }
        }
    }
}
