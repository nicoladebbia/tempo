//
// CoachInterviewServiceTests.swift
// Tempo
//
// Coach v2.1 Phase 7.5 — covers the interview-answers → LearnedPreference
// translation, UserSettings flag updates, skip-all path, and reset path.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachInterviewServiceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            UserSettings.self,
            LearnedPreference.self,
            LearnedOutcome.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Empty answers (skip-all path)

    func testPersist_emptyAnswersSetsSkippedFlag() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let report = try CoachInterviewService.persist(
            answers: CoachInterviewAnswers(),
            in: context
        )
        XCTAssertEqual(report.inserted, 0)
        XCTAssertTrue(report.skipped)
        XCTAssertFalse(report.completed)

        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertTrue(settings.coachInterviewSkipped)
        XCTAssertFalse(settings.coachInterviewCompleted)
        XCTAssertNotNil(settings.coachInterviewCompletedAt)

        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertTrue(prefs.isEmpty, "no rows on skip-all")
    }

    // MARK: - All six questions answered

    func testPersist_allAnswersInsertsSixRowsWithUserVerifiedSource() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(
            tiredMode: .askFirst,
            tonePreference: .drillSergeant,
            silentTrack: [.meals, .sleep],
            failedHabit: "intermittent fasting",
            hardDayNeverSuggest: "cold showers",
            scheduleException: "Friday fasting"
        )
        let report = try CoachInterviewService.persist(answers: answers, in: context)
        XCTAssertEqual(report.inserted, 6)
        XCTAssertTrue(report.completed)
        XCTAssertFalse(report.skipped)

        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertEqual(prefs.count, 6)
        for pref in prefs {
            XCTAssertEqual(pref.source, .userVerified)
            XCTAssertEqual(pref.confidence, 1.0, accuracy: 0.001)
            XCTAssertTrue(pref.isActive)
        }
    }

    // MARK: - Subject + polarity + scope mapping

    func testPersist_tiredModeMapsToToneSubject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(tiredMode: .push)
        _ = try CoachInterviewService.persist(answers: answers, in: context)
        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertEqual(prefs.count, 1)
        XCTAssertEqual(prefs.first?.subject, "tone.push_when_tired")
        XCTAssertEqual(prefs.first?.polarity, .positive)
        XCTAssertEqual(prefs.first?.scope, .always)
    }

    func testPersist_noPreferenceToneSkipsInsert() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(tonePreference: .noPreference)
        let report = try CoachInterviewService.persist(answers: answers, in: context)
        // "no preference" is nothing useful to learn — but it IS an answer so
        // the completed flag fires.
        XCTAssertEqual(report.inserted, 0)
        XCTAssertTrue(report.completed)

        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertTrue(prefs.isEmpty)
    }

    func testPersist_silentTrackMultiSelectJoinsLabels() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(
            silentTrack: [.meals, .sleep, .trainingIntensity]
        )
        _ = try CoachInterviewService.persist(answers: answers, in: context)
        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        let pref = try XCTUnwrap(prefs.first)
        XCTAssertEqual(pref.subject, "tone.silent_track")
        XCTAssertTrue(pref.text.contains("Meals"))
        XCTAssertTrue(pref.text.contains("Sleep"))
        XCTAssertTrue(pref.text.contains("Training intensity"))
    }

    func testPersist_failedHabitMapsToAvoidAtAllCostsRedLine() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(failedHabit: "intermittent fasting")
        _ = try CoachInterviewService.persist(answers: answers, in: context)
        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        let pref = try XCTUnwrap(prefs.first)
        XCTAssertEqual(pref.subject, "red_lines.never_suggest")
        XCTAssertEqual(pref.polarity, .avoidAtAllCosts)
        XCTAssertEqual(pref.scope, .always)
        XCTAssertTrue(pref.text.contains("intermittent fasting"))
    }

    func testPersist_hardDayNeverSuggestScopesToHardDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(hardDayNeverSuggest: "cold showers")
        _ = try CoachInterviewService.persist(answers: answers, in: context)
        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        let pref = try XCTUnwrap(prefs.first)
        XCTAssertEqual(pref.subject, "red_lines.never_suggest_on_hard_days")
        XCTAssertEqual(pref.polarity, .avoidAtAllCosts)
        XCTAssertEqual(pref.scope, .dayTypeHard)
    }

    func testPersist_scheduleExceptionMapsToScheduleSubject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(scheduleException: "Friday fasting")
        _ = try CoachInterviewService.persist(answers: answers, in: context)
        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        let pref = try XCTUnwrap(prefs.first)
        XCTAssertEqual(pref.subject, "schedule.exceptions")
        XCTAssertEqual(pref.scope, .always)
    }

    // MARK: - Whitespace-only answers ignored

    func testPersist_whitespaceFreeTextSkipped() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(
            failedHabit: "   ",
            hardDayNeverSuggest: "\n\n",
            scheduleException: ""
        )
        let report = try CoachInterviewService.persist(answers: answers, in: context)
        XCTAssertEqual(report.inserted, 0)
        XCTAssertTrue(report.skipped, "whitespace-only counts as empty across all fields")
    }

    // MARK: - Partial completion still sets completed flag

    func testPersist_partialCompletionSetsCompletedNotSkipped() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(tiredMode: .ease)
        let report = try CoachInterviewService.persist(answers: answers, in: context)
        XCTAssertEqual(report.inserted, 1)
        XCTAssertTrue(report.completed)
        XCTAssertFalse(report.skipped)

        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertTrue(settings.coachInterviewCompleted)
        XCTAssertFalse(settings.coachInterviewSkipped)
    }

    // MARK: - Idempotency / re-run

    func testPersist_reusesExistingUserSettings() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Seed an existing UserSettings row.
        let settings = UserSettings()
        context.insert(settings)
        try context.save()
        let originalID = settings.id

        let answers = CoachInterviewAnswers(tiredMode: .push)
        _ = try CoachInterviewService.persist(answers: answers, in: context)

        let all = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(all.count, 1, "must not create a second UserSettings row")
        XCTAssertEqual(all.first?.id, originalID)
        XCTAssertTrue(all.first?.coachInterviewCompleted ?? false)
    }

    // MARK: - Reset

    func testResetInterview_clearsFlags() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let answers = CoachInterviewAnswers(tiredMode: .push)
        _ = try CoachInterviewService.persist(answers: answers, in: context)
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertTrue(settings.coachInterviewCompleted)
        XCTAssertNotNil(settings.coachInterviewCompletedAt)

        try CoachInterviewService.resetInterview(in: context)

        XCTAssertFalse(settings.coachInterviewCompleted)
        XCTAssertFalse(settings.coachInterviewSkipped)
        XCTAssertNil(settings.coachInterviewCompletedAt)

        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        XCTAssertEqual(prefs.count, 1, "reset must NOT delete existing rows")
    }

    // MARK: - Answers.hasAnyAnswer

    func testHasAnyAnswer_acrossFields() {
        XCTAssertFalse(CoachInterviewAnswers().hasAnyAnswer)
        XCTAssertTrue(CoachInterviewAnswers(tiredMode: .ease).hasAnyAnswer)
        XCTAssertTrue(CoachInterviewAnswers(silentTrack: [.meals]).hasAnyAnswer)
        XCTAssertTrue(CoachInterviewAnswers(failedHabit: "x").hasAnyAnswer)
        XCTAssertFalse(CoachInterviewAnswers(failedHabit: "   ").hasAnyAnswer)
        XCTAssertFalse(CoachInterviewAnswers(scheduleException: "\n\t").hasAnyAnswer)
    }

    // MARK: - CoachVoiceMode default

    func testUserSettings_coachVoiceModeDefaultsToTapToggle() {
        let settings = UserSettings()
        XCTAssertEqual(settings.coachVoiceMode, .tapToggle)
        XCTAssertEqual(settings.coachVoiceModeRaw, "tapToggle")
    }
}
