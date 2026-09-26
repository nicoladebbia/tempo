import APNSCore
import Fluent
import Vapor
import VaporAPNS

// MARK: - APNs Service

// Per BUILD_PLAN step 12.1 — Sends push notifications via Apple Push Notification service.
// Per ADR-019 — Direct APNs with P8 token-based authentication.
// Per TECHNICAL_FEASIBILITY_AUDIT.md Section 5.4 — apnswift is production-ready.

enum APNsService {
    // MARK: - Notification Types

    // Per ONBOARDING_AND_NOTIFICATIONS.md — All notification channels.

    enum NotificationType: String, Codable, Sendable {
        case recoveryMorning = "recovery_morning"
        case accountabilityTier1 = "accountability_tier1"
        case accountabilityTier2 = "accountability_tier2"
        case accountabilityTier3 = "accountability_tier3"
        case accountabilityTier4 = "accountability_tier4"
        case mealReminder = "meal_reminder"
        case trainingReminder = "training_reminder"
        case bedtimeReminder = "bedtime_reminder"
        case streakWarning = "streak_warning"
        case leaderboardChange = "leaderboard_change"
        case challengeInvite = "challenge_invite"
        case challengeUpdate = "challenge_update"
        case achievementUnlock = "achievement_unlock"
        case weeklySummary = "weekly_summary"
        /// Per feat/weekly-plan-server — server finished building next
        /// week's meal plan (WeeklyPlanJob) and it's ready to review.
        case mealPlanReady = "meal_plan_ready"
        case general

        /// APNs category identifier for actionable notifications.
        var category: String {
            switch self {
            case .recoveryMorning: return "RECOVERY_REPORT"
            case .accountabilityTier1, .accountabilityTier2,
                 .accountabilityTier3, .accountabilityTier4: return "ACCOUNTABILITY"
            case .mealReminder: return "MEAL_REMINDER"
            case .challengeInvite: return "CHALLENGE_INVITE"
            case .achievementUnlock: return "ACHIEVEMENT"
            case .mealPlanReady: return "MEAL_PLAN_READY"
            default: return "GENERAL"
            }
        }

        /// Per TECHNICAL_FEASIBILITY_AUDIT.md Section 3.2 — Use .timeSensitive, NOT critical.
        var interruptionLevel: String {
            switch self {
            case .recoveryMorning: return "time-sensitive"
            case .accountabilityTier1: return "active"
            case .accountabilityTier2: return "time-sensitive"
            case .accountabilityTier3, .accountabilityTier4: return "time-sensitive"
            case .bedtimeReminder: return "time-sensitive"
            case .streakWarning: return "time-sensitive"
            case .leaderboardChange, .challengeUpdate: return "passive"
            case .mealPlanReady: return "time-sensitive"
            default: return "active"
            }
        }
    }

    // MARK: - Send Alert Notification

    /// Send a visible push notification to all devices for a user.
    static func sendAlert(
        to userID: String,
        title: String,
        body: String,
        subtitle: String? = nil,
        type: NotificationType = .general,
        data: [String: String] = [:],
        on req: Request
    ) async throws {
        let topic = Environment.get("APNS_TOPIC") ?? "app.tempo.ios"

        let devices = try await DeviceToken.query(on: req.db)
            .filter(\.$userID == userID)
            .all()

        guard !devices.isEmpty else {
            req.logger.info("No device tokens for user \(userID), skipping push")
            return
        }

        // Build custom payload
        var payload = data
        payload["type"] = type.rawValue
        payload["interruption_level"] = type.interruptionLevel

        let alertContent = APNSAlertNotificationContent(
            title: .raw(title),
            subtitle: subtitle.map { .raw($0) },
            body: .raw(body)
        )

        let interruptionLevel: APNSAlertNotificationInterruptionLevel = switch type.interruptionLevel {
        case "time-sensitive": .timeSensitive
        case "passive": .passive
        case "active": .active
        default: .active
        }

        for device in devices {
            do {
                try await req.apns.client.sendAlertNotification(
                    .init(
                        alert: alertContent,
                        expiration: .immediately,
                        priority: .immediately,
                        topic: topic,
                        payload: TempoNotificationPayload(data: payload),
                        category: type.category,
                        interruptionLevel: interruptionLevel
                    ),
                    deviceToken: device.token
                )
            } catch {
                req.logger.error("APNs send failed for device \(device.deviceID): \(error)")
                if Self.isInvalidTokenError(error) {
                    try? await device.delete(on: req.db)
                    req.logger.info("Removed invalid device token for device \(device.deviceID)")
                }
            }
        }
    }

    // MARK: - Send Silent Notification

    // Per ONBOARDING_AND_NOTIFICATIONS.md — Silent push triggers background data refresh.

    static func sendSilent(
        to userID: String,
        data: [String: String],
        on req: Request
    ) async throws {
        let topic = Environment.get("APNS_TOPIC") ?? "app.tempo.ios"

        let devices = try await DeviceToken.query(on: req.db)
            .filter(\.$userID == userID)
            .all()

        for device in devices {
            do {
                try await req.apns.client.sendBackgroundNotification(
                    .init(
                        expiration: .immediately,
                        topic: topic,
                        payload: TempoNotificationPayload(data: data)
                    ),
                    deviceToken: device.token
                )
            } catch {
                req.logger.error("APNs silent send failed for device \(device.deviceID): \(error)")
                if Self.isInvalidTokenError(error) {
                    try? await device.delete(on: req.db)
                }
            }
        }
    }

    // MARK: - Error Helpers

    /// Check if an APNs error indicates an invalid or unregistered device token.
    static func isInvalidTokenError(_ error: Error) -> Bool {
        guard let apnsError = error as? APNSError,
              let reason = apnsError.reason else { return false }
        let invalidReasons = ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]
        return invalidReasons.contains(reason.reason)
    }
}

// MARK: - APNs Payload

struct TempoNotificationPayload: Codable, Sendable {
    var data: [String: String]
}
