//
// AIProgramReconcileTests.swift
// Tempo
//
// Phase 2 (TRAINING_INTELLIGENCE_TO_10.md Fix 2.3/2.5) — the safety core.
// "LLM proposes, engine disposes." These are ADVERSARIAL: every test feeds
// AIProgramPlanner.reconcile an unsafe or out-of-bounds AI proposal and proves
// the deterministic floor overrides it. If any of these fail, the AI can hurt
// the user — they are the gate on the whole AI path.
//
// reconcile() is pure (nonisolated static), so no network, VM, or device.
//

@testable import Tempo
import XCTest

final class AIProgramReconcileTests: XCTestCase {

    // A floor plan for a given weekday (Monday-anchored offset).
    private func plan(
        weekdayOffsetFromMonday offset: Int,
        type: WorkoutType,
        recoveryAdjustment: Double = 1.0
    ) -> WorkoutPlan {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2 // Monday
        let monday = cal.date(from: comps)!
        let date = cal.date(byAdding: .day, value: offset, to: monday)!
        return WorkoutPlan(date: date, type: type, recoveryAdjustment: recoveryAdjustment)
    }

    private func dayName(forOffsetFromMonday offset: Int) -> String {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2
        let monday = cal.date(from: comps)!
        let date = cal.date(byAdding: .day, value: offset, to: monday)!
        return AIProgramPlanner.weekdayName(for: date, cal: cal)
    }

    private func aiDay(offset: Int, type: String, volume: Double) -> TrainingProgramDayDTO {
        TrainingProgramDayDTO(day: dayName(forOffsetFromMonday: offset),
                              workoutType: type, volumeAdjustment: volume)
    }

    // MARK: - Floor wins on TYPE

    func testAICannotTurnRestIntoTraining() {
        // Floor put a recovery-mandated REST on Monday; AI says "legs, full volume".
        let floor = [plan(weekdayOffsetFromMonday: 0, type: .rest)]
        let ai = [aiDay(offset: 0, type: "legs", volume: 1.0)]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertEqual(out[0].type, .rest, "AI must NOT override a recovery rest day into training")
    }

    func testAICannotTurnMobilityIntoTraining() {
        let floor = [plan(weekdayOffsetFromMonday: 1, type: .mobility)]
        let ai = [aiDay(offset: 1, type: "push", volume: 1.1)]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertEqual(out[0].type, .mobility, "AI must NOT override a mobility day")
    }

    func testAICannotOverrideMatchDay() {
        let floor = [plan(weekdayOffsetFromMonday: 5, type: .football)]
        let ai = [aiDay(offset: 5, type: "legs", volume: 1.0)]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertEqual(out[0].type, .football, "AI must NOT override match day")
    }

    func testAICannotInjectLegsOnFloorNonLegsDay() {
        // T-1 swapped legs→push on the floor; AI tries to put legs back.
        let floor = [plan(weekdayOffsetFromMonday: 4, type: .push)]
        let ai = [aiDay(offset: 4, type: "legs", volume: 1.0)]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertEqual(out[0].type, .push, "AI cannot change the floor's training TYPE (T-1 leg protection)")
    }

    // MARK: - Volume clamps

    func testVolumeClampedAboveCeiling() {
        // AI proposes a wild 1.5× on a green full-volume day → clamped to 1.0
        // (can't exceed the floor's own value, and the band caps at 1.1 anyway).
        let floor = [plan(weekdayOffsetFromMonday: 0, type: .push, recoveryAdjustment: 1.0)]
        let ai = [aiDay(offset: 0, type: "push", volume: 1.5)]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertLessThanOrEqual(out[0].recoveryAdjustment, 1.0, "AI can never inflate volume above the floor")
    }

    func testAICanTrimVolumeWithinBand() {
        // Floor had a green 1.0 push; AI sensibly trims to 0.85 (recovery trend).
        let floor = [plan(weekdayOffsetFromMonday: 0, type: .push, recoveryAdjustment: 1.0)]
        let ai = [aiDay(offset: 0, type: "push", volume: 0.85)]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertEqual(out[0].recoveryAdjustment, 0.85, accuracy: 0.001, "AI may trim volume within the band")
    }

    func testAICannotTrimBelowFloorBand() {
        // AI proposes 0.2 (effectively a rest); clamp floors it at 0.5 — a
        // genuine rest is a deterministic decision, not an AI volume tweak.
        let floor = [plan(weekdayOffsetFromMonday: 0, type: .push, recoveryAdjustment: 1.0)]
        let ai = [aiDay(offset: 0, type: "push", volume: 0.2)]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertEqual(out[0].recoveryAdjustment, AIProgramPlanner.minVolume, accuracy: 0.001)
    }

    func testAICannotInflateAlreadyReducedDay() {
        // Floor cut a yellow day to 0.75; AI tries to bump it to 1.1. The
        // "never above the floor" rule keeps it at 0.75.
        let floor = [plan(weekdayOffsetFromMonday: 0, type: .push, recoveryAdjustment: 0.75)]
        let ai = [aiDay(offset: 0, type: "push", volume: 1.1)]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertEqual(out[0].recoveryAdjustment, 0.75, accuracy: 0.001, "AI cannot inflate a recovery-reduced day")
    }

    // MARK: - Robustness

    func testUnmatchedAIDaysAreIgnored() {
        // AI references a day not in the floor → ignored, floor count unchanged.
        let floor = [plan(weekdayOffsetFromMonday: 0, type: .push, recoveryAdjustment: 1.0)]
        let ai = [
            aiDay(offset: 0, type: "push", volume: 0.9),
            aiDay(offset: 3, type: "legs", volume: 1.0), // no floor match
        ]
        let out = AIProgramPlanner.reconcile(ai: ai, floor: floor)
        XCTAssertEqual(out.count, 1, "Floor defines which days exist")
        XCTAssertEqual(out[0].recoveryAdjustment, 0.9, accuracy: 0.001)
    }

    func testEmptyAILeavesFloorUntouched() {
        let floor = [plan(weekdayOffsetFromMonday: 0, type: .push, recoveryAdjustment: 1.0)]
        let out = AIProgramPlanner.reconcile(ai: [], floor: floor)
        XCTAssertEqual(out[0].recoveryAdjustment, 1.0, accuracy: 0.001)
        XCTAssertEqual(out[0].type, .push)
    }

    // MARK: - Football day name mapping

    func testFootballDayNamesMapping() {
        XCTAssertEqual(AIProgramPlanner.footballDayNames(.saturday), ["saturday"])
        // ActiveDays is a bitfield struct (not OptionSet) — combine via rawValue.
        let twoDays = ActiveDays(rawValue: ActiveDays.tuesday.rawValue | ActiveDays.saturday.rawValue)
        XCTAssertEqual(Set(AIProgramPlanner.footballDayNames(twoDays)), ["tuesday", "saturday"])
    }
}
