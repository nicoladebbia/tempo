//
// SupplementScheduleEngineTests.swift
// Tempo
//
// `SupplementScheduleEngine` is pure (no SwiftData), so every test builds a
// `Supplement` + `SupplementDayContext` by hand. Coverage: the WHEN priority
// order (pinned > override > plan timing > kind default, with the name
// heuristic beating a generic kind default), anchor parsing, anchor → clock
// minutes resolution, no-plan take/skip defaults (incl. training-day
// protein), and same-minute grouping.
//

@testable import Tempo
import XCTest

final class SupplementScheduleEngineTests: XCTestCase {
    // MARK: - Helpers

    private func context(
        planDecisions: [String: SupplementDecision] = [:],
        isTrainingDay: Bool = false,
        trainingStart: Int? = nil,
        trainingEnd: Int? = nil,
        wake: Int = SupplementDayContext.defaultWakeMinutes,
        bed: Int = SupplementDayContext.defaultBedMinutes,
        meals: [SupplementMealTime] = []
    ) -> SupplementDayContext {
        SupplementDayContext(
            planDecisions: planDecisions,
            isTrainingDay: isTrainingDay,
            trainingStartMinutes: trainingStart,
            trainingEndMinutes: trainingEnd,
            wakeMinutes: wake,
            bedMinutes: bed,
            meals: meals
        )
    }

    // MARK: - WHEN priority order

    func testTimeSource_pinnedBeatsEverything() {
        let supp = Supplement(name: "Creatine", kind: .creatine)
        supp.pinnedMinutes = 9 * 60
        supp.timingAnchorOverride = .dinner
        let decision = SupplementDecision(name: "Creatine", take: true, timing: "with lunch", reason: nil)
        let source = SupplementScheduleEngine.resolveTimeSource(supplement: supp, planDecision: decision)
        XCTAssertEqual(source, .pinned)
    }

    func testTimeSource_overrideBeatsPlanTimingAndKindDefault() {
        let supp = Supplement(name: "Creatine", kind: .creatine)
        supp.timingAnchorOverride = .dinner
        let decision = SupplementDecision(name: "Creatine", take: true, timing: "with lunch", reason: nil)
        let source = SupplementScheduleEngine.resolveTimeSource(supplement: supp, planDecision: decision)
        XCTAssertEqual(source, .anchorOverride(.dinner))
    }

    func testTimeSource_planTimingBeatsKindDefault() {
        let supp = Supplement(name: "Creatine", kind: .creatine) // kind default = breakfast
        let decision = SupplementDecision(name: "Creatine", take: true, timing: "after lunch", reason: nil)
        let source = SupplementScheduleEngine.resolveTimeSource(supplement: supp, planDecision: decision)
        XCTAssertEqual(source, .planTiming(.lunch))
    }

    func testTimeSource_planTimingIgnoredWhenPlanSkips() {
        // A skip decision carries no timing signal — falls through to kind default.
        let supp = Supplement(name: "Whey", kind: .protein)
        let decision = SupplementDecision(name: "Whey", take: false, timing: "with lunch", reason: "not needed")
        let source = SupplementScheduleEngine.resolveTimeSource(supplement: supp, planDecision: decision)
        XCTAssertEqual(source, .kindDefault(.postTraining))
    }

    func testTimeSource_nameHeuristicBeatsGenericKindDefault() {
        // "Vitamin / Mineral" kind defaults to breakfast, but a magnesium name
        // should anchor to bedtime instead.
        let supp = Supplement(name: "Magnesium Glycinate", kind: .vitamin)
        let source = SupplementScheduleEngine.resolveTimeSource(supplement: supp, planDecision: nil)
        XCTAssertEqual(source, .kindDefault(.bedtime))
    }

    func testTimeSource_kindDefaultWhenNoHeuristicMatches() {
        let supp = Supplement(name: "Vitamin C", kind: .vitamin)
        let source = SupplementScheduleEngine.resolveTimeSource(supplement: supp, planDecision: nil)
        XCTAssertEqual(source, .kindDefault(.breakfast))
    }

    // MARK: - Anchor parsing (SupplementTimingParser)

    func testAnchorParsing_bedtime() {
        XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: "before bed"), .bedtime)
    }

    func testAnchorParsing_postTrainingVariants() {
        for phrase in ["post-training", "post training", "after training", "post-workout", "after workout"] {
            XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: phrase), .postTraining, phrase)
        }
    }

    func testAnchorParsing_preTrainingVariants() {
        for phrase in ["pre-training", "before training", "pre-workout", "preworkout"] {
            XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: phrase), .preTraining, phrase)
        }
    }

    func testAnchorParsing_preferredOverPostWhenBothWordsPresent() {
        // "training" alone is ambiguous — compound phrases must be checked
        // before generic substrings so this doesn't misfire.
        XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: "before training, not after"), .preTraining)
    }

    func testAnchorParsing_mealsAndWakeAndMorning() {
        XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: "with breakfast"), .breakfast)
        XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: "after lunch"), .lunch)
        XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: "with dinner"), .dinner)
        XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: "on waking"), .wake)
        XCTAssertEqual(SupplementTimingParser.anchor(fromPlanTiming: "first thing in the morning"), .breakfast)
    }

    func testAnchorParsing_unrecognizedTextReturnsNil() {
        XCTAssertNil(SupplementTimingParser.anchor(fromPlanTiming: "whenever you feel like it"))
    }

    // MARK: - Name heuristic

    func testNameHeuristic_bedtimeNames() {
        for name in ["Magnesium Glycinate", "Zinc Picolinate", "Melatonin", "Ashwagandha KSM-66", "Glycine"] {
            XCTAssertEqual(SupplementNameHeuristic.anchor(forName: name), .bedtime, name)
        }
    }

    func testNameHeuristic_breakfastNames() {
        for name in ["Vitamin D3", "Vitamin K2", "Daily Multivitamin"] {
            XCTAssertEqual(SupplementNameHeuristic.anchor(forName: name), .breakfast, name)
        }
    }

    func testNameHeuristic_dinnerNames() {
        XCTAssertEqual(SupplementNameHeuristic.anchor(forName: "Fish Oil"), .dinner)
        XCTAssertEqual(SupplementNameHeuristic.anchor(forName: "Omega-3"), .dinner)
    }

    func testNameHeuristic_trainingNames() {
        XCTAssertEqual(SupplementNameHeuristic.anchor(forName: "Caffeine Pills"), .preTraining)
        XCTAssertEqual(SupplementNameHeuristic.anchor(forName: "Pre-Workout Blend"), .preTraining)
        XCTAssertEqual(SupplementNameHeuristic.anchor(forName: "Whey Isolate"), .postTraining)
    }

    func testNameHeuristic_noMatchReturnsNil() {
        XCTAssertNil(SupplementNameHeuristic.anchor(forName: "Creatine Monohydrate"))
    }

    // MARK: - Anchor → clock minutes resolution

    func testMinutes_wakeAndBedtime() {
        let ctx = context(wake: 6 * 60 + 45, bed: 22 * 60 + 30)
        XCTAssertEqual(SupplementScheduleEngine.minutes(for: .wake, context: ctx), 6 * 60 + 45)
        XCTAssertEqual(SupplementScheduleEngine.minutes(for: .bedtime, context: ctx), 22 * 60 + 30)
    }

    func testMinutes_mealsResolveFromPlannedMealsByName() {
        let ctx = context(meals: [
            SupplementMealTime(mealNumber: 1, mealName: "Big Breakfast", minutes: 8 * 60 + 15),
            SupplementMealTime(mealNumber: 3, mealName: "Dinner", minutes: 20 * 60),
        ])
        XCTAssertEqual(SupplementScheduleEngine.minutes(for: .breakfast, context: ctx), 8 * 60 + 15)
        XCTAssertEqual(SupplementScheduleEngine.minutes(for: .dinner, context: ctx), 20 * 60)
        // No lunch meal present → falls back to the default.
        XCTAssertEqual(SupplementScheduleEngine.minutes(for: .lunch, context: ctx), SupplementDayContext.defaultLunchMinutes)
    }

    func testMinutes_mealsFallBackToPositionalNumberWhenNameDoesntMatch() {
        let ctx = context(meals: [
            SupplementMealTime(mealNumber: 1, mealName: "Meal 1", minutes: 7 * 60),
        ])
        XCTAssertEqual(SupplementScheduleEngine.minutes(for: .breakfast, context: ctx), 7 * 60)
    }

    func testMinutes_preTrainingIs30MinutesBeforeStart() {
        let ctx = context(trainingStart: 18 * 60)
        XCTAssertEqual(SupplementScheduleEngine.minutes(for: .preTraining, context: ctx), 18 * 60 - 30)
    }

    func testMinutes_postTrainingUsesEndTimeWhenKnown() {
        let ctx = context(trainingStart: 18 * 60, trainingEnd: 19 * 60 + 15)
        XCTAssertEqual(SupplementScheduleEngine.minutes(for: .postTraining, context: ctx), 19 * 60 + 15)
    }

    func testMinutes_postTrainingFallsBackToStartPlusDefaultDuration() {
        let ctx = context(trainingStart: 18 * 60, trainingEnd: nil)
        XCTAssertEqual(
            SupplementScheduleEngine.minutes(for: .postTraining, context: ctx),
            18 * 60 + SupplementDayContext.defaultTrainingDurationMinutes
        )
    }

    func testMinutes_trainingAnchorsFallBackToDefaultStartWhenNoTrainingTimeAtAll() {
        let ctx = context()
        XCTAssertEqual(
            SupplementScheduleEngine.minutes(for: .preTraining, context: ctx),
            SupplementDayContext.defaultTrainingStartMinutes - 30
        )
    }

    func testResolveMinutes_pinnedWinsOverAnyAnchor() {
        let supp = Supplement(name: "Creatine", kind: .creatine)
        supp.pinnedMinutes = 10 * 60 + 5
        let ctx = context()
        let source = SupplementScheduleEngine.resolveTimeSource(supplement: supp, planDecision: nil)
        XCTAssertEqual(SupplementScheduleEngine.resolveMinutes(source: source, supplement: supp, context: ctx), 10 * 60 + 5)
    }

    // MARK: - Take/skip: plan present

    func testTakeDecision_followsPlanTakeAndReason() {
        let supp = Supplement(name: "Whey", kind: .protein)
        let decision = SupplementDecision(name: "Whey", take: true, timing: "post-training", reason: "protein gap today")
        let (take, reason) = SupplementScheduleEngine.resolveTakeDecision(supplement: supp, planDecision: decision, isTrainingDay: false)
        XCTAssertTrue(take)
        XCTAssertEqual(reason, "protein gap today")
    }

    func testTakeDecision_planSkipUsesDefaultReasonWhenNoneGiven() {
        let supp = Supplement(name: "Whey", kind: .protein)
        let decision = SupplementDecision(name: "Whey", take: false, timing: nil, reason: nil)
        let (take, reason) = SupplementScheduleEngine.resolveTakeDecision(supplement: supp, planDecision: decision, isTrainingDay: true)
        XCTAssertFalse(take)
        XCTAssertEqual(reason, "Skip per your plan")
    }

    // MARK: - Take/skip: no plan defaults

    func testTakeDecision_noPlan_takeDailyIsAlwaysTaken() {
        let creatine = Supplement(name: "Creatine", kind: .creatine) // takeDaily seeded true
        let (take, reason) = SupplementScheduleEngine.resolveTakeDecision(supplement: creatine, planDecision: nil, isTrainingDay: false)
        XCTAssertTrue(take)
        XCTAssertEqual(reason, "Daily")
    }

    func testTakeDecision_noPlan_proteinOnlyOnTrainingDay() {
        let whey = Supplement(name: "Whey", kind: .protein)
        let (takeTrainingDay, _) = SupplementScheduleEngine.resolveTakeDecision(supplement: whey, planDecision: nil, isTrainingDay: true)
        let (takeRestDay, restReason) = SupplementScheduleEngine.resolveTakeDecision(
            supplement: whey,
            planDecision: nil,
            isTrainingDay: false
        )
        XCTAssertTrue(takeTrainingDay)
        XCTAssertFalse(takeRestDay)
        XCTAssertEqual(restReason, "Rest day — nothing to fuel")
    }

    func testTakeDecision_noPlan_preworkoutAndElectrolytesFollowTrainingDayRule() {
        let pre = Supplement(name: "Pre-Workout", kind: .preworkout)
        let electrolytes = Supplement(name: "LMNT", kind: .electrolytes)
        for supp in [pre, electrolytes] {
            let (take, _) = SupplementScheduleEngine.resolveTakeDecision(supplement: supp, planDecision: nil, isTrainingDay: true)
            XCTAssertTrue(take, supp.name)
            let (takeRest, _) = SupplementScheduleEngine.resolveTakeDecision(supplement: supp, planDecision: nil, isTrainingDay: false)
            XCTAssertFalse(takeRest, supp.name)
        }
    }

    func testTakeDecision_noPlan_everythingElseIsDaily() {
        for kind: SupplementKind in [.creatine, .omega3, .multivitamin, .vitamin, .other] {
            let supp = Supplement(name: "Item", kind: kind)
            let (take, reason) = SupplementScheduleEngine.resolveTakeDecision(supplement: supp, planDecision: nil, isTrainingDay: false)
            XCTAssertTrue(take, kind.rawValue)
            XCTAssertEqual(reason, "Daily", kind.rawValue)
        }
    }

    func testTakeDecision_explicitTakeDailyOverrideBeatsKindDefault() {
        // takeDaily explicitly true on a normally-conditional kind (protein).
        let whey = Supplement(name: "Whey", kind: .protein, takeDaily: true)
        let (take, reason) = SupplementScheduleEngine.resolveTakeDecision(supplement: whey, planDecision: nil, isTrainingDay: false)
        XCTAssertTrue(take)
        XCTAssertEqual(reason, "Daily")
    }

    // MARK: - Full dose + schedule (works with no plan at all)

    func testSchedule_worksWithNoWeeklyPlan() {
        let supplements = [
            Supplement(name: "Creatine", kind: .creatine),
            Supplement(name: "Whey", kind: .protein),
            Supplement(name: "Magnesium Glycinate", kind: .vitamin),
        ]
        let ctx = context(isTrainingDay: true, trainingStart: 18 * 60, trainingEnd: 19 * 60)
        let doses = SupplementScheduleEngine.schedule(supplements: supplements, context: ctx)
        XCTAssertEqual(doses.count, 3)
        XCTAssertTrue(doses.allSatisfy { !$0.reason.isEmpty })
        let magnesium = doses.first { $0.name == "Magnesium Glycinate" }
        XCTAssertEqual(magnesium?.anchor, .bedtime)
        XCTAssertEqual(magnesium?.minutes, SupplementDayContext.defaultBedMinutes)
    }

    func testSchedule_excludesArchivedSupplements() {
        let archived = Supplement(name: "Old", kind: .other, isArchived: true)
        let active = Supplement(name: "Active", kind: .other)
        let doses = SupplementScheduleEngine.schedule(supplements: [archived, active], context: context())
        XCTAssertEqual(doses.map(\.name), ["Active"])
    }

    func testSchedule_isSortedChronologicallyWithNameTiebreak() {
        let a = Supplement(name: "Zzz Pill", kind: .other)
        a.pinnedMinutes = 8 * 60
        let b = Supplement(name: "Aaa Pill", kind: .other)
        b.pinnedMinutes = 8 * 60
        let c = Supplement(name: "Early Bird", kind: .other)
        c.pinnedMinutes = 6 * 60
        let doses = SupplementScheduleEngine.schedule(supplements: [a, b, c], context: context())
        XCTAssertEqual(doses.map(\.name), ["Early Bird", "Aaa Pill", "Zzz Pill"])
    }

    func testDose_timeLabelAndTimingLabelFormatting() {
        let supp = Supplement(name: "Creatine", kind: .creatine)
        supp.pinnedMinutes = 9 * 60 + 5
        let dose = SupplementScheduleEngine.dose(for: supp, context: context())
        XCTAssertEqual(dose.timeLabel, "09:05")
        XCTAssertEqual(dose.timingLabel, "Fixed time")
    }

    // MARK: - Grouping

    func testGroup_groupsSameMinuteDosesTogetherAndSortsByName() {
        let doses = [
            SupplementDose(
                supplementID: UUID(),
                name: "Zinc",
                kind: .vitamin,
                dosePerServing: "",
                take: true,
                minutes: 480,
                anchor: .breakfast,
                reason: "Daily"
            ),
            SupplementDose(
                supplementID: UUID(),
                name: "Creatine",
                kind: .creatine,
                dosePerServing: "",
                take: true,
                minutes: 480,
                anchor: .breakfast,
                reason: "Daily"
            ),
            SupplementDose(
                supplementID: UUID(),
                name: "Whey",
                kind: .protein,
                dosePerServing: "",
                take: true,
                minutes: 1200,
                anchor: .postTraining,
                reason: "Training day"
            ),
        ]
        let groups = SupplementScheduleEngine.group(dosesForDay: doses)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.minutes, 480)
        XCTAssertEqual(groups.first?.names, ["Creatine", "Zinc"])
        XCTAssertEqual(groups.last?.names, ["Whey"])
    }

    func testGroup_excludesSkippedDoses() {
        let doses = [
            SupplementDose(
                supplementID: UUID(),
                name: "Whey",
                kind: .protein,
                dosePerServing: "",
                take: false,
                minutes: 480,
                anchor: .breakfast,
                reason: "Rest day"
            ),
            SupplementDose(
                supplementID: UUID(),
                name: "Creatine",
                kind: .creatine,
                dosePerServing: "",
                take: true,
                minutes: 480,
                anchor: .breakfast,
                reason: "Daily"
            ),
        ]
        let groups = SupplementScheduleEngine.group(dosesForDay: doses)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.names, ["Creatine"])
    }

    // MARK: - Monday-first weekday conversion

    func testMondayFirstWeekday_matchesConvention() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        // 2026-09-28 is a Monday.
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        XCTAssertEqual(SupplementScheduleEngine.mondayFirstWeekday(for: monday, calendar: calendar), 1)
        let sunday = try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: monday))
        XCTAssertEqual(SupplementScheduleEngine.mondayFirstWeekday(for: sunday, calendar: calendar), 7)
    }
}
