//
// CoachNotifications.swift
// Tempo
//
// Recovery Coach notifications: the server's "Session done. Weigh in now."
// push (category POST_WORKOUT_WEIGHIN) with four quick-answer buttons, and the
// local pre-match reminder (PRE_MATCH_WEIGHIN). A quick answer is stored on the
// phone only: it works with the app in the background and with no network, and
// the number is sent to the server the next time the Coach screen loads.
//

import Foundation
import os
import UserNotifications

enum CoachNotifications {
    static let postCategoryID = "POST_WORKOUT_WEIGHIN"
    static let preCategoryID = "PRE_MATCH_WEIGHIN"
    static let pushType = "post_workout_weighin"

    private static let logger = Logger(subsystem: "app.tempo", category: "coach-notifications")

    /// Added to the set `NotificationService.registerCategories` registers.
    static func categories() -> Set<UNNotificationCategory> {
        let answers = CoachQuickAnswerAction.allCases.map {
            // No `.foreground`: the button acts quietly in the background.
            UNNotificationAction(identifier: $0.rawValue, title: $0.title)
        }
        return [
            UNNotificationCategory(identifier: postCategoryID, actions: answers, intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: preCategoryID, actions: [], intentIdentifiers: [], options: []),
        ]
    }

    static func quickAnswer(forAction action: String) -> CoachQuickAnswerAction? {
        CoachQuickAnswerAction(rawValue: action)
    }

    /// The session a weigh-in push names (`data.session_id`), or nil.
    static func sessionID(from userInfo: [AnyHashable: Any]) -> String? {
        CoachPushPayload(userInfo: userInfo)?.sessionId
    }

    /// Stores the answer for the push's session. Returns the answer, or nil
    /// when the push names no session (nothing is stored).
    @discardableResult
    static func handleQuickAnswer(
        action: String, userInfo: [AnyHashable: Any], store: RecoveryCoachStore = .shared, now: Date = Date()
    ) -> CoachQuickAnswerAction? {
        guard let answer = quickAnswer(forAction: action) else { return nil }
        guard let sessionID = sessionID(from: userInfo) else {
            logger.error("quick answer without a session id; nothing stored")
            return nil
        }
        store.recordQuickAnswer(sessionID: sessionID, bottles: answer.bottles, now: now)
        return answer
    }

    /// "Noted: one bottle." Plain wording of what was stored.
    static func confirmation(for answer: CoachQuickAnswerAction, bottleMl: Int) -> String {
        switch answer {
        case .nothing: "Noted: you drank nothing."
        case .halfBottle: "Noted: half a bottle (\(bottleMl / 2) mL)."
        case .oneBottle: "Noted: one bottle (\(bottleMl) mL)."
        case .twoBottles: "Noted: two bottles (\(bottleMl * 2) mL)."
        }
    }

    /// A quiet local note after a button press, so the press doesn't feel dead.
    static func postConfirmation(_ answer: CoachQuickAnswerAction, bottleMl: Int) async {
        let content = UNMutableNotificationContent()
        content.title = confirmation(for: answer, bottleMl: bottleMl)
        content.body = "Open Tempo for what to drink and eat."
        content.userInfo = [:]
        let request = UNNotificationRequest(
            identifier: "coach.answer.confirmation", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("confirmation not shown: \(error.localizedDescription, privacy: .public)")
        }
    }
}
