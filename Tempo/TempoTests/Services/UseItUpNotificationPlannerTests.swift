//
// UseItUpNotificationPlannerTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class UseItUpNotificationPlannerTests: XCTestCase {
    private func item(_ name: String, daysOut: Int, quantity: Double = 100, isArchived: Bool = false) -> PantryItem {
        PantryItem(
            canonicalName: name, displayName: name.capitalized, quantity: quantity, unit: .grams,
            useBy: Calendar.current.date(byAdding: .day, value: daysOut, to: Date()),
            isArchived: isArchived
        )
    }

    // MARK: - decide

    func testDecide_noItemsExpiringSoon_doesNotFire() {
        let items = [item("rice", daysOut: 30), item("pasta", daysOut: 10)]
        let decision = UseItUpNotificationPlanner.decide(items: items)
        XCTAssertFalse(decision.shouldFire)
        XCTAssertEqual(decision.urgentCount, 0)
    }

    func testDecide_itemExpiringWithin2Days_fires() {
        let items = [item("milk", daysOut: 1)]
        let decision = UseItUpNotificationPlanner.decide(items: items)
        XCTAssertTrue(decision.shouldFire)
        XCTAssertEqual(decision.urgentCount, 1)
        XCTAssertTrue(decision.body.contains("Milk"))
    }

    func testDecide_itemExpiringExactlyAt2Days_fires() {
        let items = [item("milk", daysOut: 2)]
        XCTAssertTrue(UseItUpNotificationPlanner.decide(items: items).shouldFire)
    }

    func testDecide_itemExpiringAt3Days_doesNotFire() {
        let items = [item("milk", daysOut: 3)]
        XCTAssertFalse(UseItUpNotificationPlanner.decide(items: items).shouldFire, "Outside the 0-2 day window")
    }

    func testDecide_expiresToday_fires() {
        let items = [item("milk", daysOut: 0)]
        XCTAssertTrue(UseItUpNotificationPlanner.decide(items: items).shouldFire)
    }

    func testDecide_alreadyExpiredItem_isOutsideWindow() {
        // The window is 0...2 days — an item that's ALREADY past its useBy
        // (negative days) isn't caught by this notification (it'd have fired
        // on an earlier day already); confirms the window doesn't silently
        // widen to include the past.
        let items = [item("milk", daysOut: -1)]
        XCTAssertFalse(UseItUpNotificationPlanner.decide(items: items).shouldFire)
    }

    func testDecide_archivedItem_isIgnored() {
        let items = [item("milk", daysOut: 1, isArchived: true)]
        XCTAssertFalse(UseItUpNotificationPlanner.decide(items: items).shouldFire)
    }

    func testDecide_depletedItem_isIgnored() {
        let items = [item("milk", daysOut: 1, quantity: 0)]
        XCTAssertFalse(UseItUpNotificationPlanner.decide(items: items).shouldFire, "Nothing to use up if there's none left")
    }

    func testDecide_manyItems_isOneSummaryNotification() {
        let items = (0 ..< 6).map { item("food\($0)", daysOut: 1) }
        let decision = UseItUpNotificationPlanner.decide(items: items)
        XCTAssertTrue(decision.shouldFire)
        XCTAssertEqual(decision.urgentCount, 6)
        XCTAssertTrue(decision.body.contains("more"), "Body should summarize rather than list all 6")
    }

    func testDecide_noUseByDate_isIgnored() {
        let noDate = PantryItem(canonicalName: "flour", displayName: "Flour", quantity: 500, unit: .grams)
        XCTAssertFalse(UseItUpNotificationPlanner.decide(items: [noDate]).shouldFire)
    }

    // MARK: - nextMorningFireDate

    func testNextMorningFireDate_beforeEightAM_isToday() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 6
        let now = try XCTUnwrap(Calendar.current.date(from: components))

        let fireDate = UseItUpNotificationPlanner.nextMorningFireDate(after: now)

        let fireComponents = Calendar.current.dateComponents([.day, .hour], from: fireDate)
        XCTAssertEqual(fireComponents.day, 15)
        XCTAssertEqual(fireComponents.hour, 8)
    }

    func testNextMorningFireDate_afterEightAM_isTomorrow() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = 20
        let now = try XCTUnwrap(Calendar.current.date(from: components))

        let fireDate = UseItUpNotificationPlanner.nextMorningFireDate(after: now)

        let fireComponents = Calendar.current.dateComponents([.day, .hour], from: fireDate)
        XCTAssertEqual(fireComponents.day, 16)
        XCTAssertEqual(fireComponents.hour, 8)
    }
}
