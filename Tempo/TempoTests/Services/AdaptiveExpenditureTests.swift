//
// AdaptiveExpenditureTests.swift
// Tempo
//
// Maintenance calories from logged intake vs the weight trend, and how
// TDEECalculator trusts it.
//

@testable import Tempo
import XCTest

final class AdaptiveExpenditureTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func day(_ offset: Int) -> Date {
        start.addingTimeInterval(Double(offset) * 86400)
    }

    private func intake(_ kcal: Int, days: Int) -> [DailyEatenTotals] {
        (0 ..< days).map { DailyEatenTotals(date: day($0), calories: kcal, protein: 150, carbs: 250, fat: 70, mealsEaten: 4) }
    }

    /// Losing 0.5 kg/week on 2,200 kcal → maintenance ≈ 2,200 + 550 = 2,750.
    func testLosingWeightMeansMaintenanceIsAboveIntake() throws {
        let weighIns = stride(from: 0, to: 28, by: 2).map {
            AdaptiveExpenditure.WeighIn(date: day($0), kg: 80 - 0.5 / 7 * Double($0))
        }
        let observed = try XCTUnwrap(AdaptiveExpenditure.observe(intake: intake(2200, days: 28), weighIns: weighIns))
        XCTAssertEqual(observed.kcal, 2750, accuracy: 5)
        XCTAssertEqual(observed.trendKgPerWeek, -0.5, accuracy: 0.01)
        XCTAssertEqual(observed.confidence, AdaptiveExpenditure.maxConfidence, accuracy: 0.001)
    }

    func testTooLittleDataGivesNothing() {
        let weighIns = stride(from: 0, to: 28, by: 2).map { AdaptiveExpenditure.WeighIn(date: day($0), kg: 80) }
        XCTAssertNil(AdaptiveExpenditure.observe(intake: intake(2200, days: 7), weighIns: weighIns), "A week of logs isn't enough")
        let threeWeighIns = [0, 5, 20].map { AdaptiveExpenditure.WeighIn(date: day($0), kg: 80) }
        XCTAssertNil(AdaptiveExpenditure.observe(intake: intake(2200, days: 28), weighIns: threeWeighIns))
        let shortSpan = (0 ..< 6).map { AdaptiveExpenditure.WeighIn(date: day($0), kg: 80) }
        XCTAssertNil(AdaptiveExpenditure.observe(intake: intake(2200, days: 28), weighIns: shortSpan))
    }

    func testPartialLogDaysAndStrayWeighInsAreIgnored() throws {
        var days = intake(2400, days: 20)
        days += (20 ..< 28).map { DailyEatenTotals(date: day($0), calories: 450, protein: 30, carbs: 40, fat: 15, mealsEaten: 1) }
        var weighIns = stride(from: 0, to: 28, by: 2).map { AdaptiveExpenditure.WeighIn(date: day($0), kg: 80) }
        weighIns.append(.init(date: day(27), kg: 62)) // someone else on the scale
        let observed = try XCTUnwrap(AdaptiveExpenditure.observe(intake: days, weighIns: weighIns))
        XCTAssertEqual(observed.kcal, 2400, accuracy: 1, "Stable weight on real days → maintenance = intake")
        XCTAssertEqual(observed.loggedDays, 20)
        XCTAssertLessThan(observed.confidence, AdaptiveExpenditure.maxConfidence)
    }

    func testOneWeighInPerDay() {
        let morning = AdaptiveExpenditure.WeighIn(date: day(0), kg: 80)
        let evening = AdaptiveExpenditure.WeighIn(date: day(0).addingTimeInterval(3600), kg: 80.4)
        XCTAssertEqual(AdaptiveExpenditure.dedupedByDay([morning, evening]).count, 1)
    }

    // MARK: - TDEECalculator blend

    private func tdee(observed: AdaptiveExpenditure.Observation?) -> Double {
        TDEECalculator.calculate(
            weightKg: 80, heightCm: 183, age: 24, biologicalSex: .male, bodyFatPercent: nil,
            trainingFrequency: 4, whoopAverageTDEE: nil, goal: .maintain, observedExpenditure: observed
        ).tdee
    }

    func testCalculatorLeansOnObservedExpenditureByConfidence() {
        let formula = tdee(observed: nil)
        let observed = AdaptiveExpenditure.Observation(kcal: formula + 300, confidence: 0.8, loggedDays: 28, trendKgPerWeek: 0)
        XCTAssertEqual(tdee(observed: observed), formula + 240, accuracy: 0.5)
        let weak = AdaptiveExpenditure.Observation(kcal: formula + 300, confidence: 0.2, loggedDays: 10, trendKgPerWeek: 0)
        XCTAssertEqual(tdee(observed: weak), formula + 60, accuracy: 0.5)
    }

    func testCalculatorIgnoresImplausibleObservations() {
        let formula = tdee(observed: nil)
        let underLogged = AdaptiveExpenditure.Observation(kcal: formula * 0.4, confidence: 0.8, loggedDays: 28, trendKgPerWeek: 0)
        XCTAssertEqual(tdee(observed: underLogged), formula, accuracy: 0.01)
    }
}
