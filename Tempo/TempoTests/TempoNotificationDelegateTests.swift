@testable import Tempo
import Testing

struct TempoNotificationDelegateTests {
    @Test func readsTypeNestedUnderData() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": "x"],
            "data": ["type": "meal_plan_ready", "jobId": "abc"],
        ]
        #expect(TempoNotificationDelegate.pushType(from: userInfo) == "meal_plan_ready")
    }

    @Test func fallsBackToTopLevelType() {
        #expect(TempoNotificationDelegate.pushType(from: ["type": "meal_plan_ready"]) == "meal_plan_ready")
    }

    @Test func nestedTypeWinsAndMissingIsNil() {
        #expect(TempoNotificationDelegate.pushType(from: ["type": "a", "data": ["type": "b"]]) == "b")
        #expect(TempoNotificationDelegate.pushType(from: ["data": ["jobId": "1"]]) == nil)
    }
}
