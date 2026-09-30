//
// ExtraGymSessionPlannerTests.swift
// Tempo
//
// "Add gym session" on a soccer day — the pure decision: gap bands, vetoes,
// the hard-soccer cap, legs rules, gym-before-soccer, default focus, headline.
//

@testable import Tempo
import XCTest

final class ExtraGymSessionPlannerTests: XCTestCase {
    /// Soccer 10:00–11:30 unless overridden.
    private func ctx(
        gymAt: Int,
        soccer: ExtraGymContext.Soccer = .init(startMin: 600, durationMin: 90),
        acwr: Double? = nil,
        floorSevere: Bool = false,
        tomorrowFootball: Bool = false,
        tomorrow: WorkoutType? = nil,
        done: [WorkoutType] = [],
        remaining: [WorkoutType] = [],
        requested: WorkoutType? = nil
    ) -> ExtraGymContext {
        ExtraGymContext(
            soccer: soccer, gymStartMin: gymAt, acwr: acwr, floorSevere: floorSevere,
            tomorrowIsMatchOrFootball: tomorrowFootball, tomorrowType: tomorrow,
            weekDoneTypes: done, weekRemainingTypes: remaining, requestedFocus: requested
        )
    }

    func testGapUnder3hIsEasyUpper() {
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 13 * 60 + 30)) // 2h after 11:30
        XCTAssertEqual(d.intensity, .easy)
        XCTAssertTrue([.upper, .push, .pull].contains(d.focus))
        XCTAssertTrue(d.excludeHeavyLower)
    }

    func testGap4hIsModerateUpper() {
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 15 * 60 + 30))
        XCTAssertEqual(d.intensity, .moderate)
        XCTAssertNotEqual(d.focus, .mobility)
    }

    func testGap7hIsModerateAndFullBodyAllowedWithoutHeavyLegs() {
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 18 * 60 + 30, requested: .fullBody))
        XCTAssertEqual(d.intensity, .moderate)
        XCTAssertEqual(d.focus, .fullBody)
        XCTAssertTrue(d.excludeHeavyLower)
    }

    func testAcwrSpikeForcesMobility() {
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 18 * 60, acwr: 1.4))
        XCTAssertEqual(d.focus, .mobility)
        XCTAssertEqual(d.intensity, .recovery)
        XCTAssertTrue(d.options.allSatisfy { !$0.allowed })
    }

    func testFloorSevereForcesRecoveryOnly() {
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 18 * 60, floorSevere: true, requested: .push))
        XCTAssertEqual(d.focus, .mobility)
    }

    func testHardSoccerCapsGymAtModerate() {
        let hard = ExtraGymContext.Soccer(startMin: 600, durationMin: 90, strain: 15)
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 19 * 60, soccer: hard))
        XCTAssertEqual(d.soccerLoad, .hard)
        XCTAssertLessThanOrEqual(rank(d.intensity), rank(.moderate))
    }

    func testVeryHardSoccerDropsGymOneTier() {
        let brutal = ExtraGymContext.Soccer(startMin: 600, durationMin: 90, strain: 17)
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 19 * 60, soccer: brutal))
        XCTAssertEqual(d.intensity, .easy)
    }

    func testMatchCountsAsHard() {
        let match = ExtraGymContext.Soccer(startMin: 600, durationMin: 90, isMatch: true)
        XCTAssertEqual(ExtraGymSessionPlanner.soccerLoad(match), .hard)
    }

    func testLegsBlockedOnMatchAndBeforeFootballTomorrow() {
        let match = ExtraGymContext.Soccer(startMin: 600, durationMin: 90, isMatch: true)
        let d1 = ExtraGymSessionPlanner.decide(ctx(gymAt: 20 * 60, soccer: match))
        XCTAssertEqual(d1.options.first { $0.focus == .legs }?.allowed, false)
        let d2 = ExtraGymSessionPlanner.decide(ctx(gymAt: 20 * 60, tomorrowFootball: true, tomorrow: .football))
        XCTAssertEqual(d2.options.first { $0.focus == .legs }?.allowed, false)
    }

    func testLegsWarnedButAllowedAtSixHoursPlus() {
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 18 * 60 + 30, requested: .legs))
        let legs = d.options.first { $0.focus == .legs }
        XCTAssertEqual(legs?.allowed, true)
        XCTAssertNotNil(legs?.warning)
        XCTAssertEqual(d.focus, .legs)
        XCTAssertTrue(d.excludeHeavyLower)
    }

    func testLegsBlockedUnderSixHours() {
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 15 * 60, requested: .legs))
        XCTAssertEqual(d.options.first { $0.focus == .legs }?.allowed, false)
        XCTAssertNotEqual(d.focus, .legs)
    }

    func testGymBeforeSoccerIsEasy() {
        let soccer = ExtraGymContext.Soccer(startMin: 18 * 60, durationMin: 90)
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 9 * 60, soccer: soccer))
        XCTAssertEqual(d.intensity, .easy)
        XCTAssertLessThan(d.gapHours, 0)
        XCTAssertEqual(d.options.first { $0.focus == .legs }?.allowed, false)
    }

    func testDefaultFocusAvoidsTomorrowsType() {
        let d = ExtraGymSessionPlanner.decide(ctx(
            gymAt: 16 * 60, tomorrow: .pull, done: [], remaining: [.push, .pull, .upper]
        ))
        XCTAssertEqual(d.focus, .push, "Tomorrow is pull, so push today")
    }

    func testDefaultFocusPrefersOwedType() {
        let d = ExtraGymSessionPlanner.decide(ctx(
            gymAt: 16 * 60, tomorrow: .football, done: [.upper], remaining: [.pull]
        ))
        XCTAssertEqual(d.focus, .pull)
    }

    func testHeadlineNamesFocusIntensityAndWhy() {
        let d = ExtraGymSessionPlanner.decide(ctx(gymAt: 16 * 60, requested: .upper))
        XCTAssertEqual(d.headline, "Upper body, moderate")
        XCTAssertFalse(d.reasons.isEmpty)
        XCTAssertEqual(d.reasons.filter { $0.lowercased().contains("legs already") }.count, 1)
        XCTAssertTrue(d.reasons.allSatisfy { !$0.hasSuffix(".") && !$0.contains("..") })
    }

    private func rank(_ i: SessionIntensity) -> Int {
        switch i {
        case .recovery: 0
        case .easy: 1
        case .moderate: 2
        case .hard: 3
        case .max: 4
        }
    }
}
