//
// TrainerReportSupplementalSectionsTests.swift
// Tempo
//
// Pause/travel-pain feature's trainer-report additions — relabeling of
// paused/match-skipped rows, the recomputed summary, and the football/pain/
// pauses/travel-swap sections. Builds a minimal `TrainerReportDocument`
// fixture directly (mirrors `TrainerReportBuilderTests`' own pattern of
// testing this pure layer without a full SwiftData round trip).
//

@testable import Tempo
import XCTest

final class TrainerReportSupplementalSectionsTests: XCTestCase {
    private let cal = TrainingCalendar.iso8601

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)!
    }

    private func row(date: Date, status: TrainerReportSessionStatus = .missed) -> TrainerReportSessionRow {
        TrainerReportSessionRow(
            id: UUID().uuidString, scheduledDate: date, dateLabel: "x", title: "Session",
            status: status, statusLabel: "Missed", completionFraction: nil, recoveryScoreText: nil,
            exercises: [], conditioning: [], prs: [], notes: []
        )
    }

    private func baseDocument(sessions: [TrainerReportSessionRow]) -> TrainerReportDocument {
        let missed = sessions.filter { $0.status == .missed }.count
        let scheduled = sessions.count
        let summary = TrainerReportSummary(
            scheduledCount: scheduled, doneCount: scheduled - missed, missedCount: missed, movedCount: 0,
            completionRate: scheduled > 0 ? Double(scheduled - missed) / Double(scheduled) : 0,
            averageRecoveryScore: nil, painNoteCount: 0
        )
        let strings = TrainerReportStrings.forLanguage(.english)
        return TrainerReportDocument(
            language: .english, scope: .week, strings: strings, programName: "PT", title: "t",
            dateRangeLabel: "range", generatedLabel: "gen", summary: summary,
            summaryLines: ["Adherence: \(Int((summary.completionRate * 100).rounded()))% (\(summary.doneCount)/\(summary.scheduledCount))"],
            sessions: sessions
        )
    }

    // MARK: - Relabeling + summary recompute

    func testPausedMissedRowIsRelabeledAndExcludedFromMissedCount() {
        let pausedDate = date("2026-09-23")
        let unrelatedMissedDate = date("2026-09-26") // outside the pause's 22...25 range
        let doc = baseDocument(sessions: [row(date: pausedDate), row(date: unrelatedMissedDate)])
        let pause = TrainingPause(reason: .sick, startDate: date("2026-09-22"), plannedEndDate: date("2026-09-25"))

        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(pauses: [pause], matches: [], plans: [], painReports: [], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )

        XCTAssertTrue(result.sessions[0].statusLabel.lowercased().contains("sick"))
        XCTAssertEqual(result.sessions[1].statusLabel, "Missed", "outside the pause window — untouched")
        XCTAssertEqual(result.summary.missedCount, 1, "the paused row no longer counts as missed")
        XCTAssertEqual(result.summary.doneCount, 0, "unrelated to done — unchanged")
    }

    func testMatchDaySkippedRowIsRelabeled() {
        let matchDate = date("2026-09-24")
        let doc = baseDocument(sessions: [row(date: matchDate)])
        let match = Match(kickoff: matchDate)

        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(pauses: [], matches: [match], plans: [], painReports: [], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )

        XCTAssertEqual(result.sessions[0].statusLabel, "Skipped — match day")
        XCTAssertEqual(result.summary.missedCount, 0)
    }

    func testDoneRowsAreNeverTouched() {
        let doc = baseDocument(sessions: [row(date: date("2026-09-23"), status: .done)])
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(pauses: [], matches: [], plans: [], painReports: [], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )
        XCTAssertEqual(result.sessions[0].statusLabel, "Missed", "unchanged placeholder label — only .missed rows are ever relabeled")
    }

    // MARK: - Football section

    func testFootballSectionListsMatchesInScope() {
        let doc = baseDocument(sessions: [])
        let match = Match(kickoff: date("2026-09-24"), opponent: "Inter", isCompetitive: true)
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(pauses: [], matches: [match], plans: [], painReports: [], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )
        let football = result.extraSections.first { $0.title == "Football" }
        XCTAssertNotNil(football)
        // lines[0] is the weekly load summary (no Whoop data here, so just the
        // count); the match itself is the line after it.
        XCTAssertEqual(football?.lines.first, "1 session")
        XCTAssertTrue(football?.lines.last?.contains("Inter") == true)
        XCTAssertTrue(football?.lines.last?.contains("Match") == true)
    }

    func testNoFootballSectionWhenNoMatchesInScope() {
        let doc = baseDocument(sessions: [])
        let result = TrainerReportSupplementalSections.apply(
            to: doc, input: .init(scopeRange: date("2026-09-21") ... date("2026-09-27")), language: .english
        )
        XCTAssertNil(result.extraSections.first { $0.title == "Football" })
    }

    // MARK: - Pain section

    func testPainSectionListsReportsInScope() {
        let doc = baseDocument(sessions: [])
        let report = PainReport(
            date: date("2026-09-23"), bodyArea: .knee, severity: 6,
            exerciseNameSnapshot: "Back Squat", actionTaken: .swapped
        )
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(pauses: [], matches: [], plans: [], painReports: [report], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )
        let pain = result.extraSections.first { $0.title == "Pain / injury" }
        XCTAssertNotNil(pain)
        XCTAssertTrue(pain?.lines.first?.contains("Knee") == true)
        XCTAssertTrue(pain?.lines.first?.contains("Back Squat") == true)
        XCTAssertTrue(pain?.lines.first?.contains("6/10") == true)
    }

    // MARK: - Pauses section

    func testPausesSectionSummarizesRange() {
        let doc = baseDocument(sessions: [])
        let pause = TrainingPause(reason: .sick, startDate: date("2026-09-22"), plannedEndDate: date("2026-09-24"))
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(pauses: [pause], matches: [], plans: [], painReports: [], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )
        let pauses = result.extraSections.first { $0.title == "Pauses" }
        XCTAssertNotNil(pauses)
        XCTAssertTrue(pauses?.lines.first?.contains("Sick") == true)
    }

    // MARK: - Travel swap section

    func testTravelSwapSectionListsSwappedExercises() {
        let plan = WorkoutPlan(date: date("2026-09-23"), type: .push)
        let exercise = Exercise(
            name: "Dumbbell RDL",
            muscleGroup: .hamstrings,
            equipment: .dumbbell,
            movementPattern: .hinge,
            isCompound: true
        )
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        slot.travelSwapOriginalName = "Barbell RDL"
        plan.exercises = [slot]

        let doc = baseDocument(sessions: [])
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(pauses: [], matches: [], plans: [plan], painReports: [], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )
        let travel = result.extraSections.first { $0.title == "Travel adjustments" }
        XCTAssertNotNil(travel)
        XCTAssertTrue(travel?.lines.first?.contains("Barbell RDL") == true)
        XCTAssertTrue(travel?.lines.first?.contains("Dumbbell RDL") == true)
        XCTAssertTrue(travel?.lines.first?.contains("swapped") == true)
    }

    // MARK: - Italian

    func testItalianStrings() {
        let doc = baseDocument(sessions: [])
        let match = Match(kickoff: date("2026-09-24"), isCompetitive: false)
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(pauses: [], matches: [match], plans: [], painReports: [], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .italian
        )
        let football = result.extraSections.first { $0.title == "Calcio" }
        XCTAssertNotNil(football)
        XCTAssertTrue(football?.lines.last?.contains("Amichevole") == true)
    }

    // MARK: - Football section — Whoop enrichment

    func testFootballLineIncludesFullWhoopStats() {
        let matchDate = date("2026-09-26")
        let doc = baseDocument(sessions: [])
        let match = Match(kickoff: matchDate, opponent: "Inter", isCompetitive: true)
        let session = ActivitySession(
            date: matchDate, startTime: matchDate, workoutType: "football", sportID: 1,
            source: "whoop", strain: 16.2, averageHeartRate: 152, maxHeartRate: 178,
            caloriesBurned: 812, durationMinutes: 94
        )
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(matches: [match], footballActivities: [session], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )
        let football = result.extraSections.first { $0.title == "Football" }
        let matchLine = football?.lines.last
        XCTAssertTrue(matchLine?.contains("94′") == true)
        XCTAssertTrue(matchLine?.contains("strain 16.2") == true)
        XCTAssertTrue(matchLine?.contains("avg HR 152") == true)
        XCTAssertTrue(matchLine?.contains("max HR 178") == true)
        XCTAssertTrue(matchLine?.contains("812 kcal") == true)
        XCTAssertEqual(football?.lines.first, "1 session · 94′ · total strain 16.2")
    }

    func testFootballLineItalianHeartRateLabels() {
        let matchDate = date("2026-09-26")
        let doc = baseDocument(sessions: [])
        let match = Match(kickoff: matchDate, isCompetitive: true)
        let session = ActivitySession(
            date: matchDate, startTime: matchDate, workoutType: "football", sportID: 1,
            source: "whoop", strain: 16.2, averageHeartRate: 152, maxHeartRate: 178,
            caloriesBurned: 812, durationMinutes: 94
        )
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(matches: [match], footballActivities: [session], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .italian
        )
        let football = result.extraSections.first { $0.title == "Calcio" }
        let matchLine = football?.lines.last
        XCTAssertTrue(matchLine?.contains("FC media 152") == true)
        XCTAssertTrue(matchLine?.contains("FC max 178") == true)
        XCTAssertTrue(matchLine?.contains("94′") == true)
        XCTAssertTrue(matchLine?.contains("strain 16.2") == true)
        XCTAssertEqual(football?.lines.first, "1 sessione · 94′ · strain totale 16.2")
    }

    func testFootballLinePartialWhoopDataOmitsMissingFields() {
        let matchDate = date("2026-09-24")
        let doc = baseDocument(sessions: [])
        let match = Match(kickoff: matchDate, isCompetitive: false)
        // Only strain is known — e.g. a Whoop export with an incomplete row.
        let session = ActivitySession(
            date: matchDate, startTime: matchDate, workoutType: "football", sportID: 1,
            source: "whoop", strain: 9.4
        )
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(matches: [match], footballActivities: [session], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )
        let football = result.extraSections.first { $0.title == "Football" }
        let line = football?.lines.last
        XCTAssertTrue(line?.contains("Friendly") == true)
        XCTAssertTrue(line?.contains("strain 9.4") == true)
        XCTAssertFalse(line?.contains("avg HR") == true)
        XCTAssertFalse(line?.contains("kcal") == true)
        XCTAssertFalse(line?.contains("′") == true, "no duration was known — shouldn't fabricate one")
        // No duration was available anywhere this week, so the summary omits
        // the minutes segment but still totals the strain that IS known.
        XCTAssertEqual(football?.lines.first, "1 session · total strain 9.4")
    }

    func testNoWhoopDataLeavesFootballLineUnchanged() {
        let matchDate = date("2026-09-24")
        let doc = baseDocument(sessions: [])
        let match = Match(kickoff: matchDate, opponent: "Roma", isCompetitive: true)
        // Manual attestation — "I played" with no Whoop activity attached.
        let manual = ActivitySession(date: matchDate, startTime: matchDate, workoutType: "football", sportID: -1, source: "manual")
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(matches: [match], footballActivities: [manual], scopeRange: date("2026-09-21") ... date("2026-09-27")),
            language: .english
        )
        let football = result.extraSections.first { $0.title == "Football" }
        XCTAssertEqual(football?.lines.count, 2)
        XCTAssertEqual(football?.lines.first, "1 session")
        XCTAssertFalse(football?.lines.last?.contains("′") == true)
        XCTAssertFalse(football?.lines.last?.contains("strain") == true)
    }

    func testFootballStatsPrefersLongestSessionOnSameDay() {
        let day = date("2026-09-24")
        let short = ActivitySession(
            date: day, startTime: day, workoutType: "football", sportID: 1, source: "whoop",
            strain: 10.0, averageHeartRate: 140, maxHeartRate: 160, caloriesBurned: 500, durationMinutes: 45
        )
        let long = ActivitySession(
            date: day, startTime: day, workoutType: "football", sportID: 1, source: "whoop",
            strain: 16.2, averageHeartRate: 152, maxHeartRate: 178, caloriesBurned: 812, durationMinutes: 94
        )
        let stats = TrainerReportSupplementalSections.footballStats(matching: day, in: [short, long], calendar: cal)
        XCTAssertEqual(stats?.durationMinutes, 94)
        XCTAssertEqual(stats?.strain, 16.2)
    }

    func testFootballStatsReturnsNilWithNoMatchingActivity() {
        let day = date("2026-09-24")
        let otherDay = ActivitySession(
            date: date("2026-09-23"), startTime: date("2026-09-23"), workoutType: "football", sportID: 1, source: "whoop", strain: 10
        )
        XCTAssertNil(TrainerReportSupplementalSections.footballStats(matching: day, in: [otherDay], calendar: cal))
        XCTAssertNil(TrainerReportSupplementalSections.footballStats(matching: day, in: [], calendar: cal))
    }

    func testFootballWeeklySummaryLineSumsMultipleSessions() {
        let doc = baseDocument(sessions: [])
        let match1 = Match(kickoff: date("2026-09-23"), isCompetitive: true)
        let match2 = Match(kickoff: date("2026-09-26"), isCompetitive: true)
        let session1 = ActivitySession(
            date: date("2026-09-23"), startTime: date("2026-09-23"), workoutType: "football", sportID: 1,
            source: "whoop", strain: 13.2, durationMinutes: 74
        )
        let session2 = ActivitySession(
            date: date("2026-09-26"), startTime: date("2026-09-26"), workoutType: "football", sportID: 1,
            source: "whoop", strain: 16.2, durationMinutes: 94
        )
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(
                matches: [match1, match2],
                footballActivities: [session1, session2],
                scopeRange: date("2026-09-21") ... date("2026-09-27")
            ),
            language: .english
        )
        let football = result.extraSections.first { $0.title == "Football" }
        XCTAssertEqual(football?.lines.first, "2 sessions · 168′ · total strain 29.4")
    }

    func testFootballWeeklySummaryLineItalian() {
        let doc = baseDocument(sessions: [])
        let match1 = Match(kickoff: date("2026-09-23"), isCompetitive: true)
        let match2 = Match(kickoff: date("2026-09-26"), isCompetitive: true)
        let session1 = ActivitySession(
            date: date("2026-09-23"), startTime: date("2026-09-23"), workoutType: "football", sportID: 1,
            source: "whoop", strain: 13.2, durationMinutes: 74
        )
        let session2 = ActivitySession(
            date: date("2026-09-26"), startTime: date("2026-09-26"), workoutType: "football", sportID: 1,
            source: "whoop", strain: 16.2, durationMinutes: 94
        )
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(
                matches: [match1, match2],
                footballActivities: [session1, session2],
                scopeRange: date("2026-09-21") ... date("2026-09-27")
            ),
            language: .italian
        )
        let football = result.extraSections.first { $0.title == "Calcio" }
        XCTAssertEqual(football?.lines.first, "2 sessioni · 168′ · strain totale 29.4")
    }

    /// Regression — a double-header day (two REAL matches on the same
    /// calendar day) used to attribute the SAME (longest) session to both
    /// match lines, both double-counting it into the weekly total and
    /// silently dropping the shorter match's own real data. Each match must
    /// get its own nearest-kickoff session, and the total must be the SUM of
    /// the two distinct sessions.
    func testTwoMatchesSameDayEachGetOwnSessionNoDoubleCounting() {
        let day = date("2026-09-26")
        let earlyKickoff = day.addingTimeInterval(10 * 3600) // ~10:00
        let lateKickoff = day.addingTimeInterval(18 * 3600) // ~18:00
        let doc = baseDocument(sessions: [])
        let earlyMatch = Match(kickoff: earlyKickoff, opponent: "Youth", isCompetitive: false)
        let lateMatch = Match(kickoff: lateKickoff, opponent: "Inter", isCompetitive: true)
        let shortSession = ActivitySession(
            date: day, startTime: earlyKickoff, workoutType: "football", sportID: 1,
            source: "whoop", strain: 8.0, durationMinutes: 40
        )
        let longSession = ActivitySession(
            date: day, startTime: lateKickoff, workoutType: "football", sportID: 1,
            source: "whoop", strain: 16.2, durationMinutes: 94
        )
        let result = TrainerReportSupplementalSections.apply(
            to: doc,
            input: .init(
                // Deliberately out of kickoff order, to prove the matching
                // isn't relying on `matches` already being sorted.
                matches: [lateMatch, earlyMatch],
                footballActivities: [shortSession, longSession],
                scopeRange: date("2026-09-21") ... date("2026-09-27")
            ),
            language: .english
        )
        let football = result.extraSections.first { $0.title == "Football" }
        let lines = football?.lines ?? []
        XCTAssertTrue(lines.contains { $0.contains("Youth") && $0.contains("40′") && $0.contains("strain 8.0") })
        XCTAssertTrue(lines.contains { $0.contains("Inter") && $0.contains("94′") && $0.contains("strain 16.2") })
        // 40 + 94 = 134, 8.0 + 16.2 = 24.2 — the sum of the two DISTINCT
        // sessions, never 2× the longest one.
        XCTAssertEqual(lines.first, "2 sessions · 134′ · total strain 24.2")
    }

    func testFootballStatsForMatchesReturnsNilForUnmatchedMatchOnSharedDay() {
        let day = date("2026-09-26")
        let match1 = Match(kickoff: day.addingTimeInterval(10 * 3600))
        let match2 = Match(kickoff: day.addingTimeInterval(18 * 3600))
        // Only ONE session that day — one match must come back nil rather
        // than both claiming it.
        let onlySession = ActivitySession(
            date: day, startTime: day.addingTimeInterval(18 * 3600), workoutType: "football", sportID: 1,
            source: "whoop", strain: 16.2, durationMinutes: 94
        )
        let stats = TrainerReportSupplementalSections.footballStats(matching: [match1, match2], in: [onlySession], calendar: cal)
        XCTAssertEqual(stats.count, 2)
        XCTAssertNil(stats[0])
        XCTAssertEqual(stats[1]?.durationMinutes, 94)
    }
}
