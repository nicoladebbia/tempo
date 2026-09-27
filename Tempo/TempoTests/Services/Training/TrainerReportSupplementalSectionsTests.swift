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
        XCTAssertTrue(football?.lines.first?.contains("Inter") == true)
        XCTAssertTrue(football?.lines.first?.contains("Match") == true)
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
        XCTAssertTrue(football?.lines.first?.contains("Amichevole") == true)
    }
}
