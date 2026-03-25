import WatchConnectivity

// MARK: - Phone Watch Connectivity Service (iPhone Side)
// Per XCODE_PROJECT_STRUCTURE.md Section 11.5 — WCSession management on iPhone.

final class PhoneWatchConnectivityService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneWatchConnectivityService()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pushSnapshot(_ snapshot: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }

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
        // Handle quick actions from Watch
        // TODO: Process WatchQuickAction payloads
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // Handle transferUserInfo from Watch
        // TODO: Process WatchQuickAction payloads
    }
}
