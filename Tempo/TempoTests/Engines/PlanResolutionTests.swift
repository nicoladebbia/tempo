//
// PlanResolutionTests.swift
// Tempo
//
// Tier 3.1 — the data-loss invariant. planResolution decides whether an
// existing persisted day-row is KEPT or REPLACED when the week template
// disagrees (e.g. after editing football days / split). A completed or
// in-progress row is sacred and must NEVER be replaced. This is the failure
// mode that would silently eat logged training, so it's pinned by test.
//

@testable import Tempo
import XCTest

final class PlanResolutionTests: XCTestCase {
    // MARK: - Sacred rows are never replaced (the data-loss guard)

    func testCompletedIsNeverReplacedEvenWhenTypeDiffers() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .completed, existingType: .pull, templateType: .push
        )
        XCTAssertEqual(r, .keep, "A completed session is sacred — never replaced")
    }

    func testInProgressIsNeverReplaced() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .inProgress, existingType: .pull, templateType: .legs
        )
        XCTAssertEqual(r, .keep, "An in-progress session is sacred — never replaced")
    }

    func testSkippedIsNeverReplaced() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .skipped, existingType: .pull, templateType: .push
        )
        XCTAssertEqual(r, .keep, "A skipped row is not regenerated")
    }

    // MARK: - Planned rows regenerate only on a real type change

    func testPlannedWithDifferentTypeIsReplaced() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .planned, existingType: .pull, templateType: .push
        )
        XCTAssertEqual(r, .replace, "A still-planned row that disagrees with the template re-personalizes")
    }

    func testPlannedWithSameTypeIsKept() {
        let r = TrainingViewModel.planResolution(
            existingStatus: .planned, existingType: .push, templateType: .push
        )
        XCTAssertEqual(r, .keep, "No change needed when the planned type already matches")
    }

    // MARK: - §8 connect — brain-reshaped rows survive the resolution

    func testBrainReshapedRowIsKept() {
        // Planned pool → brain moved the day to rest, stashing "pool". The
        // template still says pool — the mismatch is deliberate, keep it.
        let r = TrainingViewModel.planResolution(
            existingStatus: .planned, existingType: .rest,
            existingPlannedTypeRaw: WorkoutType.pool.rawValue, templateType: .pool
        )
        XCTAssertEqual(r, .keep, "A brain-reshaped day must not be stomped on the next app-open")
    }

    func testBrainReshapedRowReplacedWhenTemplateChanged() {
        // The user edited the weekly schedule after the reshape: the stash no
        // longer matches the template → the schedule edit wins.
        let r = TrainingViewModel.planResolution(
            existingStatus: .planned, existingType: .rest,
            existingPlannedTypeRaw: WorkoutType.pool.rawValue, templateType: .legs
        )
        XCTAssertEqual(r, .replace, "A real schedule edit outranks a stale daily reshape")
    }

    // MARK: - §8 connect — modality → plan-type mapping

    func testModalityMapsDirectRawValues() {
        XCTAssertEqual(WorkoutType.fromModality("rest"), .rest)
        XCTAssertEqual(WorkoutType.fromModality("pool"), .pool)
        XCTAssertEqual(WorkoutType.fromModality("push"), .push)
    }

    func testModalityMapsBrainSynonyms() {
        XCTAssertEqual(WorkoutType.fromModality("recovery"), .rest)
        XCTAssertEqual(WorkoutType.fromModality("swim"), .pool)
        XCTAssertEqual(WorkoutType.fromModality("field"), .conditioning)
    }

    func testUnknownModalityIsNilNotAGuess() {
        XCTAssertNil(
            WorkoutType.fromModality("yoga"),
            "Unmappable modality must leave the plan row alone"
        )
    }

    // MARK: - §5 Week Plan / Today / Dashboard identity (mergePersistedIntoWeek)

    private func day(_ offset: Int, from monday: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday)!
    }

    func testTodaySlotIsSubstitutedWithThePersistedRowEvenWhilePlanned() {
        // `assembleWeekPlans` builds a FRESH transient object for today every
        // load; the persisted row (ensureTodayPlanPersisted) is the one Today
        // and the Dashboard actually read. Without the merge, Week Plan shows a
        // re-rolled .planned day next to Today's real (possibly edited) one.
        let cal = Calendar.current
        let monday = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let today = day(2, from: monday, calendar: cal)

        let transientToday = WorkoutPlan(date: today, type: .legs)
        let persistedToday = WorkoutPlan(date: today, type: .push) // e.g. swapped exercises
        let transientWeek = [transientToday]

        let merged = TrainingViewModel.mergePersistedIntoWeek(
            transientWeek, persisted: [persistedToday], today: today, calendar: cal
        )

        XCTAssertEqual(
            merged.first?.id,
            persistedToday.id,
            "Today's slot must be the persisted object, not the freshly generated one"
        )
    }

    func testCompletedDayKeepsItsCheckmarkAfterAReload() {
        // The regression: a completed EARLIER day in the week lost its
        // checkmark because the week reload replaced it with a fresh .planned
        // transient plan for the same date.
        let cal = Calendar.current
        let monday = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let tuesday = day(1, from: monday, calendar: cal)
        let today = day(3, from: monday, calendar: cal)

        let transientTuesday = WorkoutPlan(date: tuesday, type: .pull) // re-rolled, .planned
        let persistedTuesday = WorkoutPlan(date: tuesday, type: .pull)
        persistedTuesday.status = .completed

        let merged = TrainingViewModel.mergePersistedIntoWeek(
            [transientTuesday], persisted: [persistedTuesday], today: today, calendar: cal
        )

        XCTAssertEqual(merged.first?.id, persistedTuesday.id)
        XCTAssertEqual(merged.first?.status, .completed, "The checkmark must survive the week reload")
    }

    func testInProgressDayIsSubstituted() {
        let cal = Calendar.current
        let monday = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let today = day(0, from: monday, calendar: cal)

        let transientToday = WorkoutPlan(date: today, type: .upper)
        let persistedToday = WorkoutPlan(date: today, type: .upper)
        persistedToday.status = .inProgress

        let merged = TrainingViewModel.mergePersistedIntoWeek(
            [transientToday], persisted: [persistedToday], today: today, calendar: cal
        )

        XCTAssertEqual(merged.first?.id, persistedToday.id)
    }

    func testUntouchedFutureDayPassesThroughUnchanged() {
        // A future, still-.planned day with NO persisted row keeps whatever
        // `assembleWeekPlans` (or the AI hydration reconciling it in place)
        // produced — the merge must never invent substitutions out of nothing.
        let cal = Calendar.current
        let monday = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let today = day(0, from: monday, calendar: cal)
        let friday = day(4, from: monday, calendar: cal)

        let aiAdjustedFriday = WorkoutPlan(date: friday, type: .fullBody)

        let merged = TrainingViewModel.mergePersistedIntoWeek(
            [aiAdjustedFriday], persisted: [], today: today, calendar: cal
        )

        XCTAssertEqual(
            merged.first?.id,
            aiAdjustedFriday.id,
            "An AI-hydrated future day with no persisted row is never touched"
        )
    }

    func testPersistedPlannedRowOnANonTodayDayIsNotSubstituted() {
        // A stray persisted .planned row for a day that ISN'T today (e.g. a
        // dupe not yet cleaned up) must not override that day's regenerated
        // template — only today and sacred (completed/in-progress) days do.
        let cal = Calendar.current
        let monday = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let today = day(0, from: monday, calendar: cal)
        let thursday = day(3, from: monday, calendar: cal)

        let transientThursday = WorkoutPlan(date: thursday, type: .legs)
        let stalePlannedThursday = WorkoutPlan(date: thursday, type: .rest)

        let merged = TrainingViewModel.mergePersistedIntoWeek(
            [transientThursday], persisted: [stalePlannedThursday], today: today, calendar: cal
        )

        XCTAssertEqual(merged.first?.id, transientThursday.id)
    }
}
