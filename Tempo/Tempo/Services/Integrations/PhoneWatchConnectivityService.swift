//
// PhoneWatchConnectivityService.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import WatchConnectivity

// MARK: - SendableCompletion

/// Wraps a non-`@Sendable` escaping closure (e.g. WCSessionDelegate's
/// `replyHandler`, which the SDK doesn't annotate) so it can be captured by
/// code that itself must be `@Sendable`. `@unchecked` is safe here: the
/// wrapped closure is only ever invoked once, from `DispatchQueue.main.async`.
private struct SendableCompletion: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void

    init(_ handler: @escaping ([String: Any]) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ dict: [String: Any]) {
        handler(dict)
    }
}

// MARK: - PhoneWatchConnectivityService

// Per XCODE_PROJECT_STRUCTURE.md Section 11.5 — WCSession management on iPhone.

final class PhoneWatchConnectivityService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchConnectivityService()

    /// §22 — set ONCE at launch by `ServiceContainer` (`WatchActionRouter`).
    /// Returns whether the action was actually applied — the return value
    /// travels back to the watch as the message reply so a success haptic
    /// there only fires once this returns `true`. Actions arriving before
    /// the handler exists buffer in `pendingActions`.
    private var quickActionHandler: (@MainActor (WatchActionPayload) -> Bool)?
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
        handleIncoming(message, completion: nil)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        // WCSessionDelegate's `replyHandler` isn't `@Sendable`-annotated by
        // the SDK, so it can't be captured directly inside the `@Sendable`
        // `completion` closure `handleIncoming` requires (it's invoked from
        // `DispatchQueue.main.async`). Box it once — the box itself is the
        // only thing captured downstream.
        let reply = SendableCompletion(replyHandler)
        handleIncoming(message) { success in
            reply(["success": success])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncoming(userInfo, completion: nil)
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

    /// Route every decoded watch quick action to the app-level router
    /// (`ServiceContainer.watchActionRouter`, registered once at launch —
    /// §22). Actions arriving before it exists (queued userInfo delivered
    /// at launch) buffer and replay on registration — nothing the watch
    /// logged is dropped.
    func setQuickActionHandler(_ handler: @escaping @MainActor (WatchActionPayload) -> Bool) {
        DispatchQueue.main.async {
            self.quickActionHandler = handler
            let pending = self.pendingActions
            self.pendingActions = []
            for action in pending {
                _ = handler(action)
            }
        }
    }

    private func handleIncoming(_ dict: [String: Any], completion: (@Sendable (Bool) -> Void)?) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let action = try? JSONDecoder().decode(WatchActionPayload.self, from: data)
        else {
            completion?(false)
            return
        }
        DispatchQueue.main.async {
            if let handler = self.quickActionHandler {
                let success = handler(action)
                completion?(success)
            } else {
                self.pendingActions.append(action)
                // Queued, not confirmed applied — honest "not yet" rather
                // than a false success.
                completion?(false)
            }
        }
    }
}
