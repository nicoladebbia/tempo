import Foundation
import Vapor

// MARK: - Push capture (test mode)

//
// APNsService and NotificationScheduleJob call `capture` first. In test mode
// it records the exact APNs JSON the real send would produce (same shape as
// APNSwift: `aps` + the custom `data` object) and, when the test user logged
// in with a simulator UDID, delivers it to that simulator with
// `xcrun simctl push`. Returns false outside test mode so the real send runs.

enum TestModePush {
    static let simulatorBundleID = "app.tempo.Tempo.dev"

    struct Alert {
        let title: String
        let subtitle: String?
        let body: String
        let category: String
        let interruptionLevel: String
    }

    static func capture(
        app: Application,
        userID: String,
        alert: Alert?,
        data: [String: String]
    ) async -> Bool {
        guard let state = app.testMode else { return false }

        let payload = Self.payloadJSON(alert: alert, data: data)
        var push = CapturedPush(id: UUID(), userID: userID, createdAt: Date(), payload: payload, delivery: "captured")
        if let udid = state.simulator(for: userID) {
            push.delivery = await Self.deliver(payload, to: udid)
        }
        state.record(push)
        app.logger.info("[test-mode] push for \(userID) \(push.delivery): \(alert?.title ?? "(silent)")")
        return true
    }

    static func payloadJSON(alert: Alert?, data: [String: String]) -> String {
        var aps: [String: Any] = [:]
        if let alert {
            var alertDict: [String: Any] = ["title": alert.title, "body": alert.body]
            if let subtitle = alert.subtitle {
                alertDict["subtitle"] = subtitle
            }
            aps["alert"] = alertDict
            aps["category"] = alert.category
            aps["interruption-level"] = alert.interruptionLevel
            aps["sound"] = "default"
        } else {
            aps["content-available"] = 1
        }
        let root: [String: Any] = ["aps": aps, "data": data]
        let json = (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: json, as: UTF8.self)
    }

    /// Runs `xcrun simctl push <udid> <bundle> <file>` off the event loop.
    static func deliver(_ payload: String, to udid: String) async -> String {
        guard udid.range(of: #"^[0-9A-Fa-f-]{36}$"#, options: .regularExpression) != nil else {
            return "failed: bad simulator UDID"
        }
        return await Task.detached {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("tempo-push-\(UUID().uuidString).apns")
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                try Data(payload.utf8).write(to: file)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["simctl", "push", udid, simulatorBundleID, file.path]
                let errPipe = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = errPipe
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return "delivered"
                }
                let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                return "failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))"
            } catch {
                return "failed: \(error)"
            }
        }.value
    }
}
