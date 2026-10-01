import Vapor
import Fluent
import Queues
import Redis
import APNS
import APNSCore
import VaporAPNS

// MARK: - Morning Briefing Scheduled Job
// Per BUILD_PLAN step 12.4 — Sends morning briefings at user's configured time.
// Per ONBOARDING_AND_NOTIFICATIONS.md — Channel 1: Morning Briefing.
// Runs every 15 minutes, checks which users need their briefing.

struct MorningBriefingJob: AsyncScheduledJob {
    var name: String { "MorningBriefingJob" }

    func run(context: QueueContext) async throws {
        _ = try await send(app: context.application, now: context.application.now)
    }

    /// One pass: briefs every push-enabled user whose local time is in the
    /// 08:15–08:45 window and who hasn't had today's briefing. `userID` limits
    /// it to one user; `force` skips the window and the once-a-day check (the
    /// test server's "run it now"). Returns how many briefings went out.
    @discardableResult
    func send(app: Application, now: Date, userID onlyUserID: String? = nil, force: Bool = false) async throws -> Int {
        let db = app.db
        var sent = 0

        // Find all users with device tokens (i.e., push-enabled)
        let usersWithDevices = try await DeviceToken.query(on: db)
            .unique()
            .field(\.$userID)
            .all()

        // A named user is briefed even without a registered device (a
        // simulator may not have one; test mode captures the push anyway).
        let userIDs = onlyUserID.map { Set([$0]) } ?? Set(usersWithDevices.map(\.userID))
        guard !userIDs.isEmpty else { return 0 }

        let users = try await User.query(on: db)
            .filter(\.$id ~~ userIDs)
            .filter(\.$deletedAt == nil)
            .all()

        for user in users {
            guard let userID = user.id else { continue }

            // Determine if it's morning briefing time in user's timezone
            guard let tz = TimeZone(identifier: user.timezone) else { continue }
            var calendar = Calendar.current
            calendar.timeZone = tz

            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)

            // Default wake time: 8:30 AM. Send between 8:15-8:45 (15 min window).
            let wakeHour = 8
            let wakeMinute = 30

            let minutesFromWake = (hour * 60 + minute) - (wakeHour * 60 + wakeMinute)
            let inWindow = abs(minutesFromWake) <= 15

            guard inWindow || force else { continue }

            // Check we haven't already sent today (use Redis to track)
            let todayKey = "briefing:\(userID):\(Self.dateKey(now, tz: tz))"
            let alreadySent = try await app.redis.get(
                RedisKey(todayKey), as: String.self
            ).get()
            guard alreadySent == nil || force else { continue }

            // Build briefing content
            // Per ONBOARDING_AND_NOTIFICATIONS.md — Lock Screen Safety:
            // Use zone-based language in alert body, exact values in data payload.
            let recoveryZone = await fetchRecoveryZone(for: userID, on: db)
            let body = briefingBody(
                name: user.displayName.isEmpty ? user.username : user.displayName,
                recoveryZone: recoveryZone
            )

            // Create a fake request for APNs sending
            // (APNsService.sendAlert needs a Request for DB + APNs access)
            do {
                try await sendBriefingPush(
                    userID: userID,
                    title: "TEMPO",
                    subtitle: "Morning Briefing",
                    body: body,
                    recoveryZone: recoveryZone,
                    app: app,
                    db: db
                )

                // Mark as sent for today (expire at midnight + 1h)
                _ = try? await app.redis.set(
                    RedisKey(todayKey),
                    to: "sent"
                )
                _ = try? await app.redis.expire(
                    RedisKey(todayKey),
                    after: .hours(18)
                )

                sent += 1
                app.logger.info("Sent morning briefing to user \(userID)")
            } catch {
                app.logger.error("Failed to send morning briefing to user \(userID): \(error)")
            }
        }
        return sent
    }

    // MARK: - Recovery Zone

    private func fetchRecoveryZone(for userID: String, on db: Database) async -> String {
        // Query latest Whoop recovery data if available
        if let recovery = try? await WhoopRecovery.query(on: db)
            .filter(\.$user.$id == userID)
            .sort(\.$date, .descending)
            .first(),
           let score = recovery.recoveryScore {
            if score >= 67 { return "green" }
            if score >= 34 { return "yellow" }
            return "red"
        }
        return "unknown"
    }

    // MARK: - Copy Generator
    // Per ONBOARDING_AND_NOTIFICATIONS.md — Channel 1 copy (Drill Sergeant).
    // Per APP_STORE_COMPLIANCE.md — No exact health values on lock screen.

    private func briefingBody(name: String, recoveryZone: String) -> String {
        switch recoveryZone {
        case "green":
            return "Green recovery. Your body is ready. Full effort today. No excuses. Let's go."
        case "yellow":
            return "Yellow recovery. Not your best, not your worst. The plan doesn't change because you're tired. Adjust intensity, not commitment."
        case "red":
            return "Red recovery. Your body needs care today. Swapped to mobility. Study and meals still on — go easy physically."
        default:
            return "Morning, \(name). New day, new targets. Check your dashboard for today's plan."
        }
    }

    // MARK: - Send Push

    private func sendBriefingPush(
        userID: String,
        title: String,
        subtitle: String,
        body: String,
        recoveryZone: String,
        app: Application,
        db: Database
    ) async throws {
        if await TestModePush.capture(
            app: app,
            userID: userID,
            alert: .init(title: title, subtitle: subtitle, body: body, category: "MORNING_BRIEFING", interruptionLevel: "time-sensitive"),
            data: [
                "type": "recovery_morning",
                "interruption_level": "time-sensitive",
                "channel": "morning_briefing",
                "recovery_zone": recoveryZone,
            ]
        ) {
            return
        }

        let devices = try await DeviceToken.query(on: db)
            .filter(\.$userID == userID)
            .all()

        guard !devices.isEmpty else { return }

        let alertContent = APNSAlertNotificationContent(
            title: .raw(title),
            subtitle: .raw(subtitle),
            body: .raw(body)
        )

        let payload = TempoNotificationPayload(data: [
            "type": "recovery_morning",
            "interruption_level": "time-sensitive",
            "channel": "morning_briefing",
            "recovery_zone": recoveryZone
        ])

        for device in devices {
            do {
                let route = APNsService.route(for: device)
                try await app.apns.client(route.container).sendAlertNotification(
                    .init(
                        alert: alertContent,
                        expiration: .immediately,
                        priority: .immediately,
                        topic: route.topic,
                        payload: payload,
                        category: "MORNING_BRIEFING",
                        interruptionLevel: .timeSensitive
                    ),
                    deviceToken: device.token
                )
            } catch {
                app.logger.error("APNs briefing send failed for device \(device.deviceID): \(error)")
                if APNsService.isInvalidTokenError(error) {
                    try? await device.delete(on: db)
                }
            }
        }
    }

    // MARK: - Helpers

    private static func dateKey(_ date: Date, tz: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = tz
        return formatter.string(from: date)
    }
}
