//
// DayTimelineTests.swift
// TempoTests
//
// The day as a timeline: past items are done or missed, upcoming items stay
// ahead, sorting is by real time, the evening starts at the schedule's
// leisure time, and tomorrow's preview says nothing it does not know.
//

@testable import Tempo
import XCTest

final class DayTimelineTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private var midnight = Date()

    override func setUp() {
        super.setUp()
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24))!
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: midnight)!
    }

    private func input(
        now: Date,
        meals: [DayTimelineInput.MealRow] = [],
        workout: DayTimelineInput.WorkoutRow? = nil,
        events: [DayTimelineInput.EventRow] = [],
        study: [DayTimelineInput.StudyRow] = []
    ) -> DayTimelineInput {
        var input = DayTimelineInput(now: now, calendar: calendar)
        input.meals = meals
        input.workout = workout
        input.events = events
        input.study = study
        return input
    }

    private func meal(
        _ name: String, _ time: String, _ status: DayTimelineInput.MealRow.Status = .planned, eatenAt: Date? = nil
    ) -> DayTimelineInput.MealRow {
        .init(id: UUID(), name: name, scheduledTime: time, status: status, eatenAt: eatenAt, calories: 600)
    }

    private func session(
        _ status: DayTimelineInput.WorkoutRow.Status = .planned,
        window: TrainingTimePreference? = nil,
        finishedAt: Date? = nil
    ) -> DayTimelineInput.WorkoutRow {
        .init(
            name: "Push", status: status, startedAt: finishedAt?.addingTimeInterval(-3600),
            finishedAt: finishedAt, durationMinutes: finishedAt == nil ? nil : 60, window: window
        )
    }

    // MARK: Meals

    func testAnEatenMealIsDoneAtTheTimeItWasEaten() {
        let items = DayTimeline.items(input(
            now: at(14), meals: [meal("Lunch", "12:30", .eaten, eatenAt: at(13, 5))]
        ))
        XCTAssertEqual(items.first?.state, .done)
        XCTAssertEqual(items.first?.at, at(13, 5))
        XCTAssertTrue(items.first?.isPast == true)
    }

    func testAPlannedMealIsUpcomingUntilItsGraceEnds() {
        let lunch = meal("Lunch", "12:30")
        XCTAssertEqual(DayTimeline.items(input(now: at(12), meals: [lunch])).first?.state, .upcoming)
        XCTAssertEqual(DayTimeline.items(input(now: at(13, 59), meals: [lunch])).first?.state, .upcoming)
        XCTAssertEqual(DayTimeline.items(input(now: at(14, 5), meals: [lunch])).first?.state, .missed)
    }

    func testASkippedMealIsPast() {
        let items = DayTimeline.items(input(now: at(9), meals: [meal("Lunch", "12:30", .skipped)]))
        XCTAssertEqual(items.first?.state, .skipped)
        XCTAssertTrue(items.first?.isPast == true)
    }

    func testAMealTapOpensThatMeal() {
        let lunch = meal("Lunch", "12:30")
        XCTAssertEqual(DayTimeline.items(input(now: at(9), meals: [lunch])).first?.target, .meal(lunch.id))
    }

    // MARK: Workout

    func testACompletedSessionIsDoneAtItsFinishTime() {
        let item = DayTimeline.items(input(now: at(19), workout: session(.completed, finishedAt: at(17, 30)))).first
        XCTAssertEqual(item?.state, .done)
        XCTAssertEqual(item?.at, at(17, 30))
        XCTAssertEqual(item?.detail, "60 min")
        XCTAssertEqual(item?.target, .workout)
    }

    func testAPlannedSessionHasNoInventedHour() {
        let item = DayTimeline.items(input(now: at(9), workout: session(window: .evening))).first
        XCTAssertNil(item?.at)
        XCTAssertEqual(item?.windowLabel, TrainingTimePreference.evening.label)
        XCTAssertEqual(item?.state, .upcoming)
    }

    func testAPlannedSessionWithoutAWindowSaysAnyTime() {
        let item = DayTimeline.items(input(now: at(9), workout: session())).first
        XCTAssertEqual(item?.windowLabel, "Any time")
    }

    func testAPlannedSessionIsMissedOnlyAfterBedtime() {
        XCTAssertEqual(DayTimeline.items(input(now: at(22), workout: session())).first?.state, .upcoming)
        XCTAssertEqual(DayTimeline.items(input(now: at(23, 30), workout: session())).first?.state, .missed)
    }

    func testABedtimeAfterMidnightDoesNotMissTheSessionAllDay() {
        var late = input(now: at(15), workout: session())
        late.bedtimeMinutes = 30
        XCTAssertEqual(DayTimeline.items(late).first?.state, .upcoming)
        late.now = at(23, 45)
        XCTAssertEqual(DayTimeline.items(late).first?.state, .upcoming, "still before 00:30")
        late.now = at(3)
        XCTAssertEqual(DayTimeline.items(late).first?.state, .missed, "past 00:30 and before wake")
    }

    func testAnEveningSessionSortsAfterALunch() {
        let items = DayTimeline.items(input(
            now: at(9), meals: [meal("Lunch", "12:30")], workout: session(window: .evening)
        ))
        XCTAssertEqual(items.map(\.title), ["Lunch", "Push"])
    }

    func testAMorningSessionSortsBeforeALunch() {
        let items = DayTimeline.items(input(
            now: at(6), meals: [meal("Lunch", "12:30")], workout: session(window: .morning)
        ))
        XCTAssertEqual(items.map(\.title), ["Push", "Lunch"])
    }

    // MARK: Events, study, order

    func testACalendarEventIsOverInProgressOrUpcoming() {
        let event = DayTimelineInput.EventRow(title: "Lecture", start: at(10), end: at(12))
        XCTAssertEqual(DayTimeline.items(input(now: at(9), events: [event])).first?.state, .upcoming)
        XCTAssertEqual(DayTimeline.items(input(now: at(11), events: [event])).first?.state, .inProgress)
        XCTAssertEqual(DayTimeline.items(input(now: at(12, 1), events: [event])).first?.state, .over)
        XCTAssertEqual(DayTimeline.items(input(now: at(9), events: [event])).first?.target, DayItem.Target.none)
    }

    func testAFinishedStudyBlockIsDoneAndOpensStudy() {
        let item = DayTimeline.items(input(
            now: at(18), study: [.init(start: at(15), minutes: 45, subject: "Anatomy")]
        )).first
        XCTAssertEqual(item?.title, "Study, Anatomy")
        XCTAssertEqual(item?.detail, "45 min")
        XCTAssertEqual(item?.state, .done)
        XCTAssertEqual(item?.target, .study)
    }

    func testTheWholeDaySortsByTime() {
        let items = DayTimeline.items(input(
            now: at(9),
            meals: [meal("Dinner", "20:00"), meal("Breakfast", "08:00", .eaten, eatenAt: at(8, 10)), meal("Lunch", "12:30")],
            events: [.init(title: "Lecture", start: at(10), end: at(11))]
        ))
        XCTAssertEqual(items.map(\.title), ["Breakfast", "Lecture", "Lunch", "Dinner"])
    }

    func testAnEmptyDayHasNoItems() {
        XCTAssertTrue(DayTimeline.items(input(now: at(9))).isEmpty)
    }

    func testUpcomingKeepsOnlyTheFutureAndRespectsTheLimit() {
        let items = DayTimeline.items(input(
            now: at(9),
            meals: [
                meal("Breakfast", "08:00", .eaten, eatenAt: at(8)),
                meal("Lunch", "12:30"),
                meal("Snack", "16:00"),
                meal("Dinner", "20:00"),
            ]
        ))
        XCTAssertEqual(DayTimeline.upcoming(items, limit: 2).map(\.title), ["Lunch", "Snack"])
        XCTAssertEqual(DayTimeline.upcoming(items, limit: 5).count, 3)
    }

    func testUpcomingCanSkipWhatTheNextCardAlreadySays() {
        let lunch = meal("Lunch", "12:30")
        let items = DayTimeline.items(input(now: at(9), meals: [lunch, meal("Dinner", "20:00")]))
        let skipped = DayTimeline.upcoming(items, limit: 3, excluding: ["meal.\(lunch.id.uuidString)"])
        XCTAssertEqual(skipped.map(\.title), ["Dinner"])
    }

    func testABadTimeStringIsNotInventedIntoAnHour() {
        XCTAssertNil(DayTimeline.time("25:00", on: midnight, calendar: calendar))
        XCTAssertNil(DayTimeline.time("noon", on: midnight, calendar: calendar))
        XCTAssertEqual(DayTimeline.time("07:05", on: midnight, calendar: calendar), at(7, 5))
    }

    // MARK: Evening and tomorrow

    func testTheEveningStartsAtTheScheduleLeisureTime() {
        let leisure = 19 * 60 + 30
        XCTAssertFalse(DayTimeline.isEvening(now: at(19, 29), leisureMinutes: leisure, calendar: calendar))
        XCTAssertTrue(DayTimeline.isEvening(now: at(19, 30), leisureMinutes: leisure, calendar: calendar))
        XCTAssertTrue(DayTimeline.isEvening(now: at(23, 59), leisureMinutes: leisure, calendar: calendar))
        XCTAssertFalse(DayTimeline.isEvening(now: at(10), leisureMinutes: leisure, calendar: calendar))
    }

    func testTheEveningFollowsAChangedSchedule() {
        XCTAssertTrue(DayTimeline.isEvening(now: at(18), leisureMinutes: 17 * 60 + 45, calendar: calendar))
        XCTAssertFalse(DayTimeline.isEvening(now: at(18), leisureMinutes: 21 * 60, calendar: calendar))
    }

    func testTomorrowShowsOnlyWhatIsKnown() {
        let empty = TomorrowPreview(sessionName: nil, isRestDay: false, firstMeal: nil, firstTask: nil, wakeTime: "07:00")
        XCTAssertFalse(empty.hasContent)
        XCTAssertTrue(TomorrowPreview(sessionName: "Pull", isRestDay: false, firstMeal: nil, firstTask: nil, wakeTime: "07:00").hasContent)
        XCTAssertTrue(TomorrowPreview(sessionName: nil, isRestDay: true, firstMeal: nil, firstTask: nil, wakeTime: "07:00").hasContent)
        XCTAssertTrue(TomorrowPreview(
            sessionName: nil, isRestDay: false, firstMeal: .init(name: "Breakfast", time: "08:00"), firstTask: nil, wakeTime: "07:00"
        ).hasContent)
    }

    func testWakeTimeReadsAsAClock() {
        XCTAssertEqual(TomorrowPreview.clock(minutes: 7 * 60), "07:00")
        XCTAssertEqual(TomorrowPreview.clock(minutes: 6 * 60 + 5), "06:05")
        XCTAssertEqual(TomorrowPreview.clock(minutes: 0), "00:00")
    }
}
