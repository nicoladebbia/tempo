import Fluent
import Foundation
import Queues
@preconcurrency import Redis
import Vapor

// MARK: - Workout watch

/// Notices a big WHOOP workout that just finished and sends ONE push per session: "weigh in now".
/// Two triggers feed it: the WHOOP webhook (`workout.updated`, instant, once it is configured for WHOOP v2) and a
/// scheduled sweep every 10 minutes (the dependable path). Both are idempotent.
struct CoachWorkoutWatch {
    /// Remember a notified session for 3 days (longer than the window in which we would ever re-send).
    static let notifiedTTLSeconds = 3 * 24 * 3600

    /// How a push is delivered. Returns how many devices it reached. Injectable so the failure path can be tested.
    typealias Sender = @Sendable (_ userID: String, _ title: String, _ body: String, _ data: [String: String], _ req: Request) async throws -> Int

    var send: Sender = { userID, title, body, data, req in
        try await APNsService.sendAlert(to: userID, title: title, body: body, type: .postWorkoutWeighIn, data: data, on: req)
    }

    /// The words on the lock screen. Pure, so the copy is testable.
    static func message(for session: CoachSession) -> (title: String, body: String) {
        var facts: [String] = ["\(Int(session.durationMinutes.rounded())) min"]
        if let strain = session.strain { facts.append("strain \(String(format: "%.1f", strain))") }
        return (
            "Session done. Weigh in now.",
            "\(facts.joined(separator: ", ").capitalizedFirst). Step on the scale before you drink or eat, then tell me what you drank."
        )
    }

    /// Atomically claims a session: `SET key NX EX ttl`. Only ONE of several overlapping checks gets `true`.
    private func claim(_ key: RedisKey, on app: Application) async throws -> Bool {
        let reply = try await app.redis.send(
            command: "SET",
            with: [RESPValue(from: key.rawValue), RESPValue(from: "sent"), RESPValue(from: "NX"), RESPValue(from: "EX"), RESPValue(from: Self.notifiedTTLSeconds)]
        ).get()
        if case .null = reply { return false }
        return true
    }

    /// One pass for one user. Returns how many pushes actually reached a device.
    @discardableResult
    func check(userID: String, app: Application, now: Date, requireDevice: Bool = true) async throws -> Int {
        if requireDevice {
            let devices = try await DeviceToken.query(on: app.db).filter(\.$userID == userID).count()
            guard devices > 0 else { return 0 }
        }
        let req = Request(application: app, on: app.eventLoopGroup.next())
        let sessions = try await app.coachWorkoutSource.sessions(for: userID, from: now.addingTimeInterval(-6 * 3600), to: now, on: req)

        var sent = 0
        for session in sessions where CoachSessionRules.qualifies(session) && CoachSessionRules.isNotifiable(session, now: now) {
            let key = RedisKey("coach:notified:\(userID):\(session.id)")
            guard try await claim(key, on: app) else { continue }
            do {
                let text = Self.message(for: session)
                let delivered = try await send(
                    userID, text.title, text.body,
                    [
                        "session_id": session.id,
                        "session_start": CoachSessionRules.whoopTimestamp(session.start),
                        "session_end": CoachSessionRules.whoopTimestamp(session.end),
                        "deep_link": "tempo://coach/recovery/\(session.id)",
                    ],
                    req
                )
                if delivered > 0 {
                    sent += 1
                } else {
                    // Every attempt failed (APNs error, no usable device): release the claim so the next sweep retries.
                    _ = try? await app.redis.delete(key).get()
                    req.logger.warning("Coach weigh-in push reached no device for user \(userID), session \(session.id); will retry")
                }
            } catch {
                _ = try? await app.redis.delete(key).get()
                req.logger.error("Coach weigh-in push failed for user \(userID), session \(session.id): \(error)")
            }
        }
        return sent
    }
}

// MARK: - Scheduled sweep

struct CoachWorkoutWatchJob: AsyncScheduledJob {
    var name: String { "CoachWorkoutWatchJob" }

    func run(context: QueueContext) async throws {
        _ = try await sweep(app: context.application, now: context.application.now)
    }

    /// Every user with a connected, still-valid WHOOP AND a registered device. `userID` limits it to one
    /// (the test server's "run it now"). Revoked integrations are skipped: they would hit WHOOP's OAuth endpoint
    /// every 10 minutes forever for nothing.
    @discardableResult
    func sweep(app: Application, now: Date, userID only: String? = nil) async throws -> Int {
        var query = WhoopIntegration.query(on: app.db)
            .group(.or) { $0.filter(\.$lastSyncStatus == nil).filter(\.$lastSyncStatus != "token_revoked") }
        if let only {
            query = query.filter(\.$user.$id == only)
        } else {
            let withDevice = Set(try await DeviceToken.query(on: app.db).unique().field(\.$userID).all().map(\.userID))
            guard !withDevice.isEmpty else { return 0 }
            query = query.filter(\.$user.$id ~~ withDevice)
        }

        var sent = 0
        for integration in try await query.all() {
            let userID = integration.$user.id
            do {
                sent += try await CoachWorkoutWatch().check(userID: userID, app: app, now: now, requireDevice: only == nil)
            } catch {
                app.logger.error("Coach workout sweep failed for user \(userID): \(error)")
            }
        }
        return sent
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
