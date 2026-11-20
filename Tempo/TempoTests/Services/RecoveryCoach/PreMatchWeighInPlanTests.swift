//
// PreMatchWeighInPlanTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class PreMatchWeighInPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }

    func testFiresSixtyMinutesBeforeKickoff() {
        let r = PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 5)], now: now, lastWeighIn: nil)
        XCTAssertEqual(r.map(\.fireDate), [at(hours: 4)])
    }

    func testSkipsReminderAlreadyInThePast() {
        // Kickoff in 40 minutes: the reminder time (-20 min) is gone.
        XCTAssertTrue(PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 40.0 / 60)], now: now, lastWeighIn: nil).isEmpty)
        // Exactly now is not "after now".
        XCTAssertTrue(PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 1)], now: now, lastWeighIn: nil).isEmpty)
    }

    func testOnlyTheNextSevenDays() {
        let inside = at(hours: 7 * 24 + 1) // fire = exactly 7 days out
        let outside = at(hours: 7 * 24 + 1.1)
        let r = PreMatchWeighInPlan.reminders(kickoffs: [inside, outside], now: now, lastWeighIn: nil)
        XCTAssertEqual(r.map(\.kickoff), [inside])
    }

    func testDeduplicatesAndSorts() {
        let a = at(hours: 30), b = at(hours: 30.2), c = at(hours: 10)
        let r = PreMatchWeighInPlan.reminders(kickoffs: [a, b, c, c], now: now, lastWeighIn: nil)
        XCTAssertEqual(r.map(\.kickoff), [c, a])
    }

    func testSkipsWhenWeighedWithin90MinutesBeforeFiring() {
        let kickoff = at(hours: 3) // fires at +2 h
        XCTAssertTrue(PreMatchWeighInPlan.reminders(kickoffs: [kickoff], now: now, lastWeighIn: at(hours: 0.6)).isEmpty)
        XCTAssertEqual(PreMatchWeighInPlan.reminders(kickoffs: [kickoff], now: now, lastWeighIn: at(hours: 0.4)).count, 1)
    }

    func testOldWeighInDoesNotSuppress() {
        XCTAssertEqual(PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 3)], now: now, lastWeighIn: at(hours: -20)).count, 1)
    }

    func testIdentifiersAreStablePerKickoff() {
        let a = PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 5)], now: now, lastWeighIn: nil)
        let b = PreMatchWeighInPlan.reminders(kickoffs: [at(hours: 5)], now: now, lastWeighIn: nil)
        XCTAssertEqual(a.first?.identifier, b.first?.identifier)
        XCTAssertTrue(a.first?.identifier.hasPrefix(PreMatchWeighInPlan.idPrefix) == true)
    }

    func testKickoffsMergeMatchesAndFootballBlocks() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let day = cal.startOfDay(for: now)
        let out = PreMatchWeighInPlan.kickoffs(
            matchKickoffs: [at(hours: 2)], footballBlocks: [(day: day, startMinuteOfDay: 19 * 60)], calendar: cal
        )
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[1], day.addingTimeInterval(19 * 3600))
    }
}
