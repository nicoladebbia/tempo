import Foundation
import WatchConnectivity

// MARK: - Watch Connectivity Service (Watch Side)
// Per APPLE_WATCH_APP.md Section 5 — WCSession management on Watch.
// Per XCODE_PROJECT_STRUCTURE.md Section 11.4

@Observable
final class WatchConnectivityService: NSObject, @unchecked Sendable {
    static let shared = WatchConnectivityService()

    var latestSnapshot: WatchSnapshot = .placeholder
    var isReachable: Bool = false

    private override init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendAction(_ action: WatchQuickAction, payload: [String: String] = [:]) {
        let actionPayload = WatchActionPayload(action: action, payload: payload)
        guard let data = try? JSONEncoder().encode(actionPayload),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(dict)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
        // Load latest context on activation
        if let context = session.receivedApplicationContext as? [String: Any],
           let snapshot = WatchSnapshot.from(dictionary: context) {
            DispatchQueue.main.async {
                self.latestSnapshot = snapshot
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let snapshot = WatchSnapshot.from(dictionary: message) {
            DispatchQueue.main.async {
                self.latestSnapshot = snapshot
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let snapshot = WatchSnapshot.from(dictionary: applicationContext) {
            DispatchQueue.main.async {
                self.latestSnapshot = snapshot
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
}
