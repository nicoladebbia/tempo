//
// CoachNotificationsTests.swift
// Tempo
//

@testable import Tempo
import UserNotifications
import XCTest

final class CoachNotificationsTests: XCTestCase {
    private let id = "00000000-0000-0000-0000-000000000001"
    private var pushInfo: [AnyHashable: Any] {
        ["aps": ["category": "POST_WORKOUT_WEIGHIN"],
         "data": ["type": "post_workout_weighin", "session_id": id, "session_start": "2026-01-01T00:00:00.000Z"]]
    }

    private func store() -> RecoveryCoachStore {
        RecoveryCoachStore(defaults: UserDefaults(suiteName: "coach-n-\(UUID().uuidString)")!, key: "k")
    }

    func testCategoryHasTheFourQuickAnswersWithoutForeground() throws {
        let post = try XCTUnwrap(CoachNotifications.categories().first { $0.identifier == "POST_WORKOUT_WEIGHIN" })
        XCTAssertEqual(post.actions.map(\.title), ["Nothing", "Half a bottle", "One bottle", "Two bottles"])
        XCTAssertTrue(post.actions.allSatisfy { !$0.options.contains(.foreground) })
        XCTAssertTrue(CoachNotifications.categories().contains { $0.identifier == "PRE_MATCH_WEIGHIN" })
    }

    func testQuickAnswersAreQuietAndDefaultTapOpensCoach() {
        for action in CoachQuickAnswerAction.allCases {
            XCTAssertNil(NotificationRouter.destination(category: "POST_WORKOUT_WEIGHIN", action: action.rawValue, userInfo: pushInfo))
        }
        let tap = NotificationRouter.destination(
            category: "POST_WORKOUT_WEIGHIN", action: NotificationRouter.defaultActionID, userInfo: pushInfo
        )
        XCTAssertEqual(tap?.tab, .nutrition)
        XCTAssertEqual(tap?.coachSessionID, id)
    }

    func testPushWithoutRegisteredCategoryStillRoutesByType() {
        let tap = NotificationRouter.destination(category: "", action: NotificationRouter.defaultActionID, userInfo: pushInfo)
        XCTAssertEqual(tap?.coachSessionID, id)
    }

    func testPreMatchTapOpensNutritionToday() {
        let tap = NotificationRouter.destination(category: "PRE_MATCH_WEIGHIN", action: NotificationRouter.defaultActionID, userInfo: [:])
        XCTAssertEqual(tap?.tab, .nutrition)
        XCTAssertEqual(tap?.nutritionSection, .today)
        XCTAssertNil(tap?.coachSessionID)
    }

    func testHandlerStoresAnswerForTheSessionUsingBottleSize() {
        let s = store()
        s.update { $0.bottleMl = 500 }
        let answer = CoachNotifications.handleQuickAnswer(action: "COACH_DRANK_TWO", userInfo: pushInfo, store: s)
        XCTAssertEqual(answer, .twoBottles)
        XCTAssertEqual(s.read().quickAnswers[id]?.liters, 1.0)
    }

    func testHandlerStoresNothingWithoutSessionIDOrForOtherActions() {
        let s = store()
        XCTAssertNil(CoachNotifications.handleQuickAnswer(action: "COACH_DRANK_ONE", userInfo: ["data": ["type": "post_workout_weighin"]], store: s))
        XCTAssertNil(CoachNotifications.handleQuickAnswer(action: "DONE", userInfo: pushInfo, store: s))
        XCTAssertTrue(s.read().quickAnswers.isEmpty)
    }

    func testConfirmationWording() {
        XCTAssertEqual(CoachNotifications.confirmation(for: .nothing, bottleMl: 750), "Noted: you drank nothing.")
        XCTAssertEqual(CoachNotifications.confirmation(for: .halfBottle, bottleMl: 750), "Noted: half a bottle (375 mL).")
    }
}
