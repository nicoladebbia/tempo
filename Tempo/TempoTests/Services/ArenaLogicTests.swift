//
// ArenaLogicTests.swift
// TempoTests
//
// The small rules the Arena is built on: the week every screen and the server
// agree on, the sentences built from counts (no "1 days left"), challenge date
// math, invite-link parsing, the share card picture, and the home's numbers.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ArenaLogicTests: XCTestCase {
    private let calendar = ArenaCalendar.calendar(timeZone: TimeZone(identifier: "Europe/Rome")!)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Calendar

    func testWeekStartsOnMondayWhateverTheDay() {
        // Tue 24 Nov 2026 .. Sun 29 Nov 2026 all belong to the week of Mon 23 Nov.
        let monday = date(2026, 11, 23, hour: 0)
        for day in 23 ... 29 {
            XCTAssertEqual(ArenaCalendar.weekStart(containing: date(2026, 11, day), calendar: calendar), monday, "day \(day)")
        }
        XCTAssertEqual(
            ArenaCalendar.weekStart(containing: date(2026, 11, 30), calendar: calendar),
            date(2026, 11, 30, hour: 0)
        )
    }

    func testPreviousWeekAndDayKeys() {
        let now = date(2026, 11, 24)
        XCTAssertEqual(ArenaCalendar.previousWeekStart(before: now, calendar: calendar), date(2026, 11, 16, hour: 0))
        XCTAssertEqual(ArenaCalendar.dayKey(now, calendar: calendar), "2026-11-24")
        XCTAssertEqual(ArenaCalendar.date(forKey: "2026-11-24", calendar: calendar), date(2026, 11, 24, hour: 0))
        XCTAssertNil(ArenaCalendar.date(forKey: "not-a-day", calendar: calendar))
    }

    func testWeekAcrossAYearBoundaryUsesTheISOWeek() {
        // Fri 1 Jan 2027 is in the ISO week that started Mon 28 Dec 2026.
        XCTAssertEqual(
            ArenaCalendar.weekStart(containing: date(2027, 1, 1), calendar: calendar),
            date(2026, 12, 28, hour: 0)
        )
    }

    // MARK: - Sentences

    func testCountsAgreeWithTheNumber() {
        XCTAssertEqual(ArenaText.count(1, "day"), "1 day")
        XCTAssertEqual(ArenaText.count(0, "day"), "0 days")
        XCTAssertEqual(ArenaText.count(2, "day"), "2 days")
        XCTAssertEqual(ArenaText.count(1, "request"), "1 request")
        XCTAssertEqual(ArenaText.count(1200, "workout"), "1,200 workouts")
        XCTAssertEqual(ArenaText.count(2, "person", plural: "people"), "2 people")
    }

    func testDaysLeftNeverSaysOneDays() {
        XCTAssertEqual(ArenaText.daysLeft(0), "Last day")
        XCTAssertEqual(ArenaText.daysLeft(-3), "Last day")
        XCTAssertEqual(ArenaText.daysLeft(1), "1 day left")
        XCTAssertEqual(ArenaText.daysLeft(5), "5 days left")
        XCTAssertEqual(ArenaText.startsIn(1), "Starts tomorrow")
        XCTAssertEqual(ArenaText.startsIn(3), "Starts in 3 days")
        XCTAssertEqual(ArenaText.rank(2, of: 5), "#2 of 5")
        XCTAssertEqual(ArenaText.more(3), "+3 more")
    }

    func testMetricsFormatTheirScores() {
        XCTAssertEqual(ArenaChallengeMetric.xpTotal.format(1240), "1,240 XP")
        XCTAssertEqual(ArenaChallengeMetric.workoutCount.format(1), "1 workout")
        XCTAssertEqual(ArenaChallengeMetric.workoutCount.format(3), "3 workouts")
        XCTAssertEqual(ArenaChallengeMetric.studyMinutes.format(45), "45 min")
        XCTAssertEqual(ArenaChallengeMetric.studyMinutes.format(90), "1h 30m")
        // Only what the app really measures can be chosen.
        XCTAssertEqual(ArenaChallengeMetric.allCases.map(\.rawValue), ["xp_total", "workout_count", "study_minutes"])
    }

    // MARK: - Challenge dates

    private func challenge(
        start: String = "2026-11-20", end: String = "2026-11-26", status: String = "active", myStatus: String = "joined"
    ) -> ArenaChallengeDTO {
        ArenaChallengeDTO(
            id: "c1", isCreator: true, title: "Race", description: "", type: "group", metric: "xp_total",
            startDay: start, endDay: end, maxParticipants: 10, visibility: "friends_only", status: status,
            myStatus: myStatus, myScore: 0, myRank: nil, memberCount: 1, participants: [], createdAt: Date()
        )
    }

    func testChallengeDaysLeftAndTimeline() {
        let c = challenge()
        let now = date(2026, 11, 24)
        XCTAssertEqual(c.daysLeft(now: now, calendar: calendar), 2)
        XCTAssertEqual(c.timeLine(now: now, calendar: calendar), "2 days left")
        XCTAssertEqual(c.daysLeft(now: date(2026, 11, 25), calendar: calendar), 1)
        XCTAssertEqual(c.timeLine(now: date(2026, 11, 25), calendar: calendar), "1 day left")
        XCTAssertEqual(c.timeLine(now: date(2026, 11, 26), calendar: calendar), "Last day")
        // 20th to 26th is 7 days; on the 24th five of them have started.
        XCTAssertEqual(c.timelineProgress(now: now, calendar: calendar), 5.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(c.timelineProgress(now: date(2026, 12, 30), calendar: calendar), 1)
        XCTAssertEqual(c.timelineProgress(now: date(2026, 11, 1), calendar: calendar), 0)
    }

    func testUpcomingAndFinishedChallengeLines() {
        let upcoming = challenge(start: "2026-11-25", end: "2026-12-01", status: "upcoming")
        XCTAssertEqual(upcoming.timeLine(now: date(2026, 11, 24), calendar: calendar), "Starts tomorrow")
        XCTAssertEqual(upcoming.timeLine(now: date(2026, 11, 22), calendar: calendar), "Starts in 3 days")
        let done = challenge(status: "completed")
        XCTAssertEqual(done.timeLine(now: date(2026, 11, 24), calendar: calendar), "Finished")
        XCTAssertTrue(done.isFinished)
        XCTAssertTrue(challenge(myStatus: "invited").isInvitation)
    }

    // MARK: - Invite links

    func testInviteTokenFromBothLinkForms() throws {
        XCTAssertEqual(try ArenaInviteLink.token(from: XCTUnwrap(URL(string: "tempo://invite/a1b2c3d4e5f6g7h8"))), "a1b2c3d4e5f6g7h8")
        XCTAssertEqual(
            try ArenaInviteLink.token(from: XCTUnwrap(URL(string: "https://tempo.example/i/a1b2c3d4e5f6g7h8"))),
            "a1b2c3d4e5f6g7h8"
        )
        XCTAssertEqual(
            try ArenaInviteLink.token(from: XCTUnwrap(URL(string: "https://localhost:8080/i/a1b2c3d4e5f6g7h8?x=1"))),
            "a1b2c3d4e5f6g7h8"
        )
    }

    func testInviteTokenRejectsAnythingElse() throws {
        for text in [
            "tempo://invite/", "tempo://invite", "tempo://other/a1b2c3d4e5f6g7h8", "https://x.example/i/short",
            "https://x.example/join/a1b2c3d4e5f6g7h8", "https://x.example/i/a1b2c3d4-e5f6g7h8",
        ] {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertNil(ArenaInviteLink.token(from: url), text)
        }
    }

    // MARK: - Share card

    func testEveryShareLayoutRendersARealPicture() throws {
        let cards: [ShareCardContent] = [
            .workout(title: "Push day", minutes: 52, exercises: 6, sets: 22, volumeKg: 8420),
            .record(exercise: "Bench press", value: "100", unit: "kg", previous: "97.5 kg"),
            .streak(days: 14, longest: 30, level: 5),
            .week(xp: 640, workouts: 3, studyMinutes: 125, rank: 2, friends: 3, weekStart: date(2026, 11, 16, hour: 0)),
            .achievement(name: "Iron Novice", xp: 50, rarity: "Common"),
        ]
        for card in cards {
            let image = try XCTUnwrap(ShareCard.image(for: card), card.title)
            XCTAssertEqual(image.size.width * image.scale, 1080, accuracy: 1)
            XCTAssertEqual(image.size.height * image.scale, 1350, accuracy: 1)
        }
    }

    func testShareCardsCarryOnlyTheNumbersTheyWereGiven() {
        let workout = ShareCardContent.workout(title: "Pull day", minutes: nil, exercises: 5, sets: 18)
        XCTAssertEqual(workout.hero, "18")
        XCTAssertEqual(workout.heroUnit, "sets")
        XCTAssertTrue(workout.stats.isEmpty, "no minutes and no volume: nothing is invented")

        let streak = ShareCardContent.streak(days: 1)
        XCTAssertEqual(streak.heroUnit, "day")
        XCTAssertTrue(streak.stats.isEmpty)
        XCTAssertEqual(ShareCardContent.streak(days: 9, longest: 9).stats.count, 0, "best run only when it is longer")

        let week = ShareCardContent.week(xp: 0, workouts: 1, studyMinutes: 0, weekStart: date(2026, 11, 16, hour: 0))
        XCTAssertEqual(week.stats.count, 2, "no rank without friends")
        XCTAssertEqual(week.stats.first?.label, "Workout")
    }

    // MARK: - Home numbers

    func testHomeLeaderboardPreviewKeepsYouVisible() {
        func entry(_ rank: Int, me: Bool = false) -> ArenaLeaderboardRankingDTO {
            ArenaLeaderboardRankingDTO(
                rank: rank, user: ArenaLeaderboardUserDTO(id: "u\(rank)", displayName: "P\(rank)", level: 1),
                xp: 100 - rank, isMe: me
            )
        }
        let top = (1 ... 6).map { entry($0, me: $0 == 5) }
        let preview = ArenaMainView.preview(top)
        XCTAssertEqual(preview.map(\.rank), [1, 2, 3, 5])
        XCTAssertEqual(ArenaMainView.preview((1 ... 3).map { entry($0, me: $0 == 2) }).map(\.rank), [1, 2, 3])
        XCTAssertTrue(ArenaMainView.preview([]).isEmpty)
    }

    func testRecapShowsOnMondayAndTuesdayOnly() {
        // Calendar weekday: 1 Sunday, 2 Monday, 3 Tuesday ...
        XCTAssertEqual((1 ... 7).filter { ArenaMainView.showsRecap(weekday: $0) }, [2, 3])
    }

    func testViewModelNumbersComeFromTheLedgerRows() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        let context = ModelContext(container)
        let now = date(2026, 11, 24)
        let startOfToday = calendar.startOfDay(for: now)
        let lastWeek = date(2026, 11, 17, hour: 18)
        /// XPEvent cuts its own day with the device calendar; pin the day the Arena's calendar means.
        func insert(_ day: Date, _ source: XPSource, _ amount: Int, _ text: String) {
            let event = XPEvent(date: day, source: source, amount: amount, description: text)
            event.date = day
            context.insert(event)
        }
        insert(startOfToday, .workout, 100, "Finished a workout")
        insert(startOfToday, .meal, 15, "Logged meals")
        insert(calendar.startOfDay(for: lastWeek), .study, 60, "50 minutes of focus")
        try context.save()

        let summary = ArenaXPLedger.Summary(
            totalXP: 175, level: 1, today: "2026-11-24",
            days: [
                ArenaStatsDayDTO(day: "2026-11-24", xp: 115, workouts: 1, studyMinutes: 0),
                ArenaStatsDayDTO(day: "2026-11-17", xp: 60, workouts: 0, studyMinutes: 50),
            ],
            newlyEarned: [], xpByDay: ["2026-11-24": 115, "2026-11-17": 60]
        )
        let vm = ArenaViewModel(xpEngine: XPEngine())
        vm.load(in: context, summary: summary, now: now, calendar: calendar)

        XCTAssertEqual(vm.todayXP, 115)
        XCTAssertEqual(vm.totalXP, 175, "one total: the sum of the rows")
        XCTAssertEqual(vm.level, XPEngine().currentLevel(totalXP: 175))
        XCTAssertEqual(vm.levelTitle, LevelSystem.displayTitle(for: vm.level))
        XCTAssertEqual(vm.weekXP, 115)
        XCTAssertEqual(vm.weekWorkouts, 1)
        XCTAssertEqual(vm.lastWeekXP, 60, "last week is the previous ISO week, not the last seven days")
        XCTAssertEqual(vm.lastWeekStudyMinutes, 50)
        XCTAssertEqual(Set(vm.xpBreakdown.map(\.source)), [.workout, .meal])
        XCTAssertEqual(vm.recentDays.first?.total, 115)
        XCTAssertFalse(vm.showXPGain, "the first load never plays the +XP overlay")
    }
}
