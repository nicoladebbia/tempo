//
// PredictionAccuracyTests.swift
// Tempo
//
// Step 2 (measurement spine) — proves the error metric is correct and, most
// importantly, that the TREND detection actually fires: a shrinking error reads
// as `.improving`. That trend is the literal definition of "adapts correctly /
// measurably right over time," so these tests are the contract for the whole
// realistic-intelligence claim. Pure — no device/store.
//

@testable import Tempo
import XCTest

final class PredictionAccuracyTests: XCTestCase {

    private let exID = UUID()

    /// A resolved prediction `daysAgo` old with a given RPE error
    /// (actual = predicted + error). predicted RPE fixed at 8.
    private func row(daysAgo: Int, error: Double, exercise: UUID? = nil) -> PredictionLog {
        let log = PredictionLog(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            exerciseID: exercise ?? exID,
            workoutPlanID: UUID(),
            predictedWeight: 100, predictedReps: 8, predictedRPE: 8.0,
            signalUsedRaw: ProgressionReason.standardProgression.rawValue
        )
        log.actualRPE = 8.0 + error
        log.outcomeResolved = true
        return log
    }

    /// Unresolved / no-RPE rows that must be excluded from scoring.
    private func unresolvedRow() -> PredictionLog {
        PredictionLog(
            exerciseID: exID, workoutPlanID: UUID(),
            predictedWeight: 100, predictedReps: 8,
            signalUsedRaw: ProgressionReason.standardProgression.rawValue
        )
    }

    // MARK: - Mean error

    func testMeanAbsErrorIsCorrect() {
        let summary = PredictionAccuracy.summarize([
            row(daysAgo: 3, error: 1.0),
            row(daysAgo: 2, error: -2.0),
            row(daysAgo: 1, error: 0.0),
        ])
        // |1| + |−2| + |0| = 3, /3 = 1.0
        XCTAssertEqual(summary.overallMeanAbsError, 1.0, accuracy: 0.001)
        XCTAssertEqual(summary.totalScored, 3)
    }

    func testSignedErrorRevealsDirection() {
        // Consistently harder than predicted → positive signed error.
        let summary = PredictionAccuracy.summarize([
            row(daysAgo: 3, error: 1.5),
            row(daysAgo: 2, error: 2.0),
        ])
        XCTAssertGreaterThan(summary.perExercise.first!.meanSignedError, 0,
                             "Systematic over-prescription should read as positive signed error")
    }

    func testExcludesUnresolvedAndNoRPE() {
        let summary = PredictionAccuracy.summarize([
            row(daysAgo: 1, error: 1.0),
            unresolvedRow(),
        ])
        XCTAssertEqual(summary.totalScored, 1, "Unresolved / no-RPE rows must not be scored")
    }

    func testEmptyIsInsufficient() {
        let summary = PredictionAccuracy.summarize([])
        XCTAssertEqual(summary.totalScored, 0)
        XCTAssertEqual(summary.overallTrend, .insufficient)
    }

    // MARK: - Trend (the definition of the whole thing)

    func testShrinkingErrorReadsAsImproving() {
        // Older half: big errors. Recent half: small errors. → improving.
        let logs = [
            row(daysAgo: 12, error: 2.5),
            row(daysAgo: 11, error: -2.0),
            row(daysAgo: 10, error: 2.2),
            row(daysAgo: 3, error: 0.2),
            row(daysAgo: 2, error: -0.1),
            row(daysAgo: 1, error: 0.0),
        ]
        let summary = PredictionAccuracy.summarize(logs)
        XCTAssertEqual(summary.overallTrend, .improving, "Error shrinking over time must read as improving")
    }

    func testGrowingErrorReadsAsWorsening() {
        let logs = [
            row(daysAgo: 12, error: 0.1),
            row(daysAgo: 11, error: 0.0),
            row(daysAgo: 10, error: -0.2),
            row(daysAgo: 3, error: 2.5),
            row(daysAgo: 2, error: -2.2),
            row(daysAgo: 1, error: 2.0),
        ]
        let summary = PredictionAccuracy.summarize(logs)
        XCTAssertEqual(summary.overallTrend, .worsening)
    }

    func testFlatErrorReadsAsStable() {
        let logs = (1 ... 6).map { row(daysAgo: 7 - $0, error: $0.isMultiple(of: 2) ? 1.0 : -1.0) }
        let summary = PredictionAccuracy.summarize(logs)
        XCTAssertEqual(summary.overallTrend, .stable, "Constant-magnitude error is stable, not a trend")
    }

    func testTooFewSamplesIsInsufficient() {
        let logs = [row(daysAgo: 2, error: 1.0), row(daysAgo: 1, error: 0.5)]
        let summary = PredictionAccuracy.summarize(logs)
        XCTAssertEqual(summary.overallTrend, .insufficient, "Below minWindow*2 → can't call a trend")
    }

    // MARK: - Per-exercise grouping

    func testPerExerciseGroupingAndWorstFirst() {
        let accurate = UUID(), sloppy = UUID()
        let logs = [
            row(daysAgo: 2, error: 0.1, exercise: accurate),
            row(daysAgo: 1, error: -0.1, exercise: accurate),
            row(daysAgo: 2, error: 2.5, exercise: sloppy),
            row(daysAgo: 1, error: -2.5, exercise: sloppy),
        ]
        let summary = PredictionAccuracy.summarize(logs)
        XCTAssertEqual(summary.perExercise.count, 2)
        XCTAssertEqual(summary.perExercise.first!.exerciseID, sloppy,
                       "Worst-predicted exercise should sort first")
    }

    // MARK: - Session-level spine (§14 #3 sRPE)

    /// A session pair `daysAgo` old. expected fixed at 6; actual = 6 + error.
    private func pair(daysAgo: Int, error: Int) -> SessionRPEPair {
        SessionRPEPair(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            expected: 6,
            actual: 6 + error
        )
    }

    func testSessionSummaryEmptyIsInsufficient() {
        XCTAssertEqual(PredictionAccuracy.summarizeSessions([]), .empty)
    }

    func testSessionMeanErrorsAreCorrect() {
        let s = PredictionAccuracy.summarizeSessions([
            pair(daysAgo: 3, error: 2),
            pair(daysAgo: 2, error: -1),
            pair(daysAgo: 1, error: 0),
        ])
        XCTAssertEqual(s.sampleCount, 3)
        XCTAssertEqual(s.meanAbsError, 1.0, accuracy: 0.001)
        XCTAssertEqual(s.meanSignedError, 1.0 / 3.0, accuracy: 0.001,
                       "Positive signed error = sessions feel harder than predicted")
    }

    func testSessionTrendImprovingWhenErrorShrinks() {
        // Older half off by 3, recent half spot-on → improving.
        let pairs = [
            pair(daysAgo: 6, error: 3), pair(daysAgo: 5, error: 3), pair(daysAgo: 4, error: 3),
            pair(daysAgo: 3, error: 0), pair(daysAgo: 2, error: 0), pair(daysAgo: 1, error: 0),
        ]
        XCTAssertEqual(PredictionAccuracy.summarizeSessions(pairs).trend, .improving)
    }

    func testSessionTrendSortsByDateNotInputOrder() {
        // Same pairs fed REVERSED — the summary must sort by date itself,
        // or the trend would read backwards (.worsening).
        let pairs = [
            pair(daysAgo: 1, error: 0), pair(daysAgo: 2, error: 0), pair(daysAgo: 3, error: 0),
            pair(daysAgo: 4, error: 3), pair(daysAgo: 5, error: 3), pair(daysAgo: 6, error: 3),
        ]
        XCTAssertEqual(PredictionAccuracy.summarizeSessions(pairs).trend, .improving)
    }

    func testSessionTrendInsufficientBelowTwoWindows() {
        let pairs = [pair(daysAgo: 3, error: 1), pair(daysAgo: 2, error: 1), pair(daysAgo: 1, error: 1)]
        XCTAssertEqual(PredictionAccuracy.summarizeSessions(pairs).trend, .insufficient)
    }
}
