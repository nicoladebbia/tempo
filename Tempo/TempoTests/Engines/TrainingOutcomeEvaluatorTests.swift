//
// TrainingOutcomeEvaluatorTests.swift
// Tempo
//
// Phase 4 (TRAINING_INTELLIGENCE_TO_10.md Fix 4.4) — outcome validation, the
// self-correction core. Proves the week grader rewards progress-without-
// overreach, penalizes overreach and missed sessions, and that the graded
// outcome actually moves the AdaptiveProfile (the macro feedback loop closes).
// All pure — no device/network/store.
//

@testable import Tempo
import XCTest

final class TrainingOutcomeEvaluatorTests: XCTestCase {

    private func row(
        day: Int,
        exID: UUID,
        weight: Double,
        volume: Double = 1000,
        avgRPE: Double? = nil,
        form: FormQuality = .clean,
        sampleCount: Int = 0
    ) -> ExerciseHistory {
        let ex = Exercise(
            name: "Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        ex.id = exID
        return ExerciseHistory(
            date: Calendar.current.date(byAdding: .day, value: -day, to: Date())!,
            totalVolume: volume,
            bestSetWeight: weight,
            bestSetReps: 8,
            avgRPE: avgRPE,
            worstFormRaw: form.rawValue,
            feedbackSampleCount: sampleCount,
            exercise: ex
        )
    }

    // MARK: - Quality scoring

    func testProgressWithoutOverreachScoresHigh() {
        let exID = UUID()
        // Two sessions, load went up, clean moderate RPE, both planned days done.
        let week = [
            row(day: 5, exID: exID, weight: 100, avgRPE: 7, sampleCount: 3),
            row(day: 2, exID: exID, weight: 105, avgRPE: 7, sampleCount: 3),
        ]
        let outcome = TrainingOutcomeEvaluator.evaluate(
            lastWeek: week, plannedTrainingDays: 2, priorWeekVolume: 1500
        )
        XCTAssertEqual(outcome.progressionHits, 1)
        XCTAssertEqual(outcome.overreachEvents, 0)
        XCTAssertGreaterThanOrEqual(outcome.qualityScore, 0.6, "Clean progress should score high")
    }

    func testOverreachPenalizesScore() {
        let exID = UUID()
        let clean = TrainingOutcomeEvaluator.evaluate(
            lastWeek: [
                row(day: 5, exID: exID, weight: 100, avgRPE: 7, sampleCount: 3),
                row(day: 2, exID: exID, weight: 105, avgRPE: 7, sampleCount: 3),
            ],
            plannedTrainingDays: 2, priorWeekVolume: 1500
        )
        let overreached = TrainingOutcomeEvaluator.evaluate(
            lastWeek: [
                row(day: 5, exID: exID, weight: 100, avgRPE: 9.5, sampleCount: 3),
                row(day: 2, exID: exID, weight: 105, avgRPE: 9.5, sampleCount: 3),
            ],
            plannedTrainingDays: 2, priorWeekVolume: 1500
        )
        XCTAssertGreaterThan(overreached.overreachEvents, 0)
        XCTAssertLessThan(overreached.qualityScore, clean.qualityScore, "Overreach must lower the score")
    }

    func testMissedSessionsPenalizeScore() {
        let exID = UUID()
        // Planned 4 days, only 1 logged → 3 missed.
        let outcome = TrainingOutcomeEvaluator.evaluate(
            lastWeek: [row(day: 3, exID: exID, weight: 100, avgRPE: 7, sampleCount: 3)],
            plannedTrainingDays: 4, priorWeekVolume: 1000
        )
        XCTAssertEqual(outcome.missedSessions, 3)
        XCTAssertLessThan(outcome.qualityScore, 0.6, "Heavy missed sessions should drag the score down")
    }

    func testEmptyWeekScoresZero() {
        let outcome = TrainingOutcomeEvaluator.evaluate(
            lastWeek: [], plannedTrainingDays: 4, priorWeekVolume: 1000
        )
        XCTAssertEqual(outcome.qualityScore, 0)
        XCTAssertEqual(outcome.missedSessions, 4)
    }

    func testNetVolumeChangeTracksTrend() {
        let exID = UUID()
        let outcome = TrainingOutcomeEvaluator.evaluate(
            lastWeek: [row(day: 2, exID: exID, weight: 100, volume: 2000, avgRPE: 7, sampleCount: 3)],
            plannedTrainingDays: 1, priorWeekVolume: 1500
        )
        XCTAssertEqual(outcome.netVolumeChange, 500, accuracy: 0.01)
    }

    // MARK: - The 10: the feedback loop closes

    func testLowQualityOutcomeDampsProfileIncrements() {
        let profile = AdaptiveProfile()
        let exID = UUID()
        profile.learnedIncrements[exID] = 5.0
        let badWeek = WeekOutcome(
            progressionHits: 0, overreachEvents: 2, missedSessions: 1,
            netVolumeChange: -300, qualityScore: 0.3
        )
        AdaptiveProfileUpdater.applyOutcome(badWeek, to: profile)
        XCTAssertLessThan(profile.learnedIncrements[exID]!, 5.0, "Overreach week must damp learned increments")
        XCTAssertGreaterThan(profile.recoveryThresholdOffset, 0, "And nudge thresholds conservative")
    }

    func testHighQualityOutcomePermitsMoreAggression() {
        let profile = AdaptiveProfile()
        let exID = UUID()
        profile.learnedIncrements[exID] = 3.0
        let greatWeek = WeekOutcome(
            progressionHits: 4, overreachEvents: 0, missedSessions: 0,
            netVolumeChange: 400, qualityScore: 0.9
        )
        AdaptiveProfileUpdater.applyOutcome(greatWeek, to: profile)
        XCTAssertGreaterThan(profile.learnedIncrements[exID]!, 3.0, "Clean productive week may permit bigger steps")
    }

    func testMiddlingOutcomeLeavesProfileUntouched() {
        let profile = AdaptiveProfile()
        let exID = UUID()
        profile.learnedIncrements[exID] = 4.0
        let okWeek = WeekOutcome(
            progressionHits: 1, overreachEvents: 0, missedSessions: 1,
            netVolumeChange: 0, qualityScore: 0.6
        )
        AdaptiveProfileUpdater.applyOutcome(okWeek, to: profile)
        XCTAssertEqual(profile.learnedIncrements[exID]!, 4.0, accuracy: 0.001, "A middling week shouldn't move increments")
    }
}
