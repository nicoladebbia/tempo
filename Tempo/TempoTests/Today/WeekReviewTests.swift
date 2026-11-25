//
// WeekReviewTests.swift
// TempoTests
//
// The week in review: which days belong to which week, the totals, and the
// one sentence per area that compares with the week before.
//

@testable import Tempo
import XCTest

final class WeekReviewTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    /// Monday 23 Nov 2026.
    private var thisMonday = Date()
    private var lastMonday = Date()

    override func setUp() {
        super.setUp()
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        thisMonday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday)!
    }

    private func day(_ monday: Date, _ offset: Int, configure: (inout WeekReviewDay) -> Void) -> WeekReviewDay {
        var row = WeekReviewDay(date: calendar.date(byAdding: .day, value: offset, to: monday)!)
        configure(&row)
        return row
    }

    private func review(_ days: [WeekReviewDay], now: Int = 6) -> WeekReview {
        WeekReviewBuilder.build(
            days: days, now: calendar.date(byAdding: .day, value: now, to: thisMonday)!, calendar: calendar
        )
    }

    // MARK: Which week

    func testTheWeekStartsOnMonday() throws {
        for offset in 0 ... 6 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: thisMonday))
            XCTAssertEqual(WeekReviewBuilder.monday(of: date, calendar: calendar), thisMonday, "day \(offset)")
        }
        let nextMonday = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: thisMonday))
        XCTAssertEqual(WeekReviewBuilder.monday(of: nextMonday, calendar: calendar), nextMonday)
    }

    func testDaysFallIntoTheirOwnWeek() {
        let result = review([
            day(thisMonday, 0) { $0.sessions = 1 },
            day(thisMonday, 6) { $0.sessions = 1 },
            day(lastMonday, 0) { $0.sessions = 1 },
            day(lastMonday, 6) { $0.sessions = 1 },
            day(lastMonday, -1) { $0.sessions = 1 },
        ])
        XCTAssertEqual(result.thisWeek.sessions, 2)
        XCTAssertEqual(result.lastWeek.sessions, 2)
        XCTAssertEqual(result.weekStart, thisMonday)
    }

    func testAMondayMorningReviewsTheWeekThatJustStarted() {
        let result = review([day(thisMonday, 0) { $0.sessions = 1 }], now: 0)
        XCTAssertEqual(result.thisWeek.sessions, 1)
    }

    // MARK: Totals

    func testTrainingTotalsAdd() {
        let totals = WeekReviewBuilder.totals([
            day(thisMonday, 0) { $0.sessions = 1; $0.trainingMinutes = 60; $0.volumeKg = 9000 },
            day(thisMonday, 2) { $0.sessions = 1; $0.trainingMinutes = 45; $0.volumeKg = 6000 },
        ])
        XCTAssertEqual(totals.sessions, 2)
        XCTAssertEqual(totals.trainingMinutes, 105)
        XCTAssertEqual(totals.volumeKg, 15000)
    }

    func testFoodAveragesOnlyTheDaysSomethingWasEaten() {
        let totals = WeekReviewBuilder.totals([
            day(thisMonday, 0) { $0.mealsEaten = 3; $0.kcal = 2800; $0.protein = 180 },
            day(thisMonday, 1) { $0.mealsEaten = 4; $0.kcal = 3000; $0.protein = 200 },
            day(thisMonday, 2) { _ in },
        ])
        XCTAssertEqual(totals.foodDays, 2)
        XCTAssertEqual(totals.avgKcal, 2900)
        XCTAssertEqual(totals.avgProtein, 190)
    }

    func testRecoveryAveragesOnlyTheDaysWithAReading() {
        let totals = WeekReviewBuilder.totals([
            day(thisMonday, 0) { $0.recoveryScore = 80; $0.sleepHours = 8 },
            day(thisMonday, 1) { $0.recoveryScore = 61; $0.sleepHours = 6 },
            day(thisMonday, 2) { _ in },
        ])
        XCTAssertEqual(totals.recoveryDays, 2)
        XCTAssertEqual(totals.avgRecovery, 71)
        XCTAssertEqual(totals.avgSleepHours ?? 0, 7, accuracy: 0.001)
    }

    func testTasksStudyAndPerfectDays() {
        let totals = WeekReviewBuilder.totals([
            day(thisMonday, 0) { $0.tasksDone = 3; $0.tasksTotal = 3; $0.studyMinutes = 90 },
            day(thisMonday, 1) { $0.tasksDone = 2; $0.tasksTotal = 3; $0.studyMinutes = 30 },
            day(thisMonday, 2) { _ in },
        ])
        XCTAssertEqual(totals.tasksDone, 5)
        XCTAssertEqual(totals.tasksTotal, 6)
        XCTAssertEqual(totals.studyMinutes, 120)
        XCTAssertEqual(totals.perfectDays, 1)
        XCTAssertEqual(totals.completionRate ?? 0, 5.0 / 6.0, accuracy: 0.0001)
    }

    func testAWeekWithNothingIsEmptyAndHasNoRate() {
        let totals = WeekReviewBuilder.totals([])
        XCTAssertTrue(totals.isEmpty)
        XCTAssertNil(totals.completionRate)
        XCTAssertNil(totals.avgKcal)
        XCTAssertNil(totals.avgRecovery)
    }

    // MARK: Sentences

    func testTrainingSentenceComparesWithLastWeek() {
        var week = WeekTotals(sessions: 4, trainingMinutes: 255)
        var last = WeekTotals(sessions: 3)
        XCTAssertEqual(WeekReviewWords.training(week, last), "4 sessions, 4h 15m in the gym, 1 session more than last week.")
        last.sessions = 5
        XCTAssertEqual(WeekReviewWords.training(week, last), "4 sessions, 4h 15m in the gym, 1 session fewer than last week.")
        last.sessions = 4
        XCTAssertEqual(
            WeekReviewWords.training(week, last),
            "4 sessions, 4h 15m in the gym, the same as last week."
        )
        week.sessions = 1
        week.trainingMinutes = 50
        last.sessions = 0
        XCTAssertEqual(WeekReviewWords.training(week, last), "1 session, 50m in the gym.")
    }

    func testTrainingSentenceWithNoSession() {
        XCTAssertEqual(WeekReviewWords.training(WeekTotals(), WeekTotals()), "No session logged this week.")
        XCTAssertEqual(
            WeekReviewWords.training(WeekTotals(), WeekTotals(sessions: 3)),
            "No session logged yet. Last week you did 3 sessions."
        )
    }

    func testFoodSentence() {
        let week = WeekTotals(foodDays: 6, avgKcal: 2850, avgProtein: 190)
        let last = WeekTotals(foodDays: 5, avgKcal: 2700, avgProtein: 170)
        XCTAssertEqual(
            WeekReviewWords.food(week, last),
            "Logged 6 days, averaging \(2850.formatted()) kcal and 190 g protein. Protein up 20 g on last week."
        )
        XCTAssertEqual(WeekReviewWords.food(WeekTotals(), last), "No meals logged this week.")
        XCTAssertFalse(WeekReviewWords.food(week, WeekTotals()).contains("last week"))
    }

    func testRecoverySentence() {
        let week = WeekTotals(recoveryDays: 7, avgRecovery: 64, avgSleepHours: 7.5)
        let last = WeekTotals(recoveryDays: 7, avgRecovery: 70)
        XCTAssertEqual(WeekReviewWords.recovery(week, last), "Recovery averaged 64%, down 6 points. You slept 7h 30m a night.")
        XCTAssertEqual(WeekReviewWords.recovery(WeekTotals(), last), "No recovery readings this week.")
    }

    func testDisciplineSentence() {
        var week = WeekTotals(tasksDone: 18, tasksTotal: 21, studyMinutes: 300)
        var last = WeekTotals(tasksDone: 14, tasksTotal: 21, studyMinutes: 240)
        XCTAssertEqual(
            WeekReviewWords.discipline(week, last),
            "18 of 21 tasks done (86%), up 19 points, 5h of study (+1h)."
        )
        week = WeekTotals()
        last = WeekTotals()
        XCTAssertEqual(WeekReviewWords.discipline(week, last), "No tasks or study logged this week.")
    }

    func testEverySentenceReadsOnAnEmptyWeek() {
        let result = review([])
        XCTAssertTrue(result.thisWeek.isEmpty)
        for line in [result.training, result.food, result.recovery, result.discipline] {
            XCTAssertFalse(line.isEmpty)
            XCTAssertTrue(line.hasSuffix("."))
        }
    }

    func testDurationAndCountPieces() {
        XCTAssertEqual(WeekReviewWords.duration(minutes: 135), "2h 15m")
        XCTAssertEqual(WeekReviewWords.duration(minutes: 45), "45m")
        XCTAssertEqual(WeekReviewWords.count(1, "day"), "1 day")
        XCTAssertEqual(WeekReviewWords.count(2, "day"), "2 days")
    }

    func testTheHeadlineNamesWhatHappened() {
        let result = review([
            day(thisMonday, 0) { $0.sessions = 1; $0.tasksTotal = 3; $0.tasksDone = 3 },
            day(thisMonday, 1) { $0.sessions = 1; $0.recoveryScore = 70 },
            day(thisMonday, 2) { $0.tasksTotal = 3; $0.tasksDone = 1 },
        ])
        XCTAssertEqual(result.headline, "2 sessions, 1 day with every task done, recovery 70%.")
    }

    func testTheHeadlineStartsWithACapitalAndSurvivesAnEmptyWeek() {
        let onlyRecovery = review([day(thisMonday, 1) { $0.recoveryScore = 64 }])
        XCTAssertEqual(onlyRecovery.headline, "Recovery 64%.")
        XCTAssertEqual(review([]).headline, "A look at how the week went.")
    }
}
