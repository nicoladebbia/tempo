//
// TwoADayPromptTests.swift
// Tempo
//
// Requirement (b), AI enrichment: when the weekly planner marks today a gym+
// cardio two-a-day, the daily-brain prompt must CARRY that decision so the AI
// keeps/refines the second session with full context instead of being blind to
// it — while still being told to DROP it on poor readiness. Pins the prompt
// assembly (the unit-testable half; the brain's actual choice is an LLM call
// governed by the system prompt's two-a-day rules and the safety floor).
//

@testable import Tempo
import XCTest

final class TwoADayPromptTests: XCTestCase {
    /// Full-field readiness — the two-a-day line is driven by the userMessage
    /// params (plannedModality / plannedSecondary), not the picture, so a plain
    /// green picture is enough.
    private func picture() -> ReadinessPicture {
        ReadinessPicture(
            recoveryScore: 75, hrv: 60, rhr: 50, respRate: 14, sleepHours: 8,
            sleepDebt: 0, dayStrain: 10, deepSleepMin: 90,
            hrvZScore: 0, hrvTrend7d: .flat, rhrDeltaBpm: 0, rhrZScore: 0,
            respDeltaBrMin: 0, acuteChronicStrainRatio: 1.0, yesterdaySessions: [],
            weightKg: 80, bodyFatPct: 12, leanMassKg: 68, checkIn: nil,
            daysUntilNextMatch: nil, validBaselineSampleCount: 30, historyDayCount: 30
        )
    }

    func testTwoADayPromptCarriesTheSecondSession() {
        let msg = DailyCoachPrompt.userMessage(for: picture(), plannedModality: "push", plannedSecondary: "run")
        XCTAssertTrue(msg.contains("TWO-A-DAY"), "The planned two-a-day must be named to the brain")
        XCTAssertTrue(msg.contains("push"), "The lift modality is carried")
        XCTAssertTrue(msg.contains("run"), "The second-session cardio modality is carried")
        XCTAssertTrue(msg.contains("6h"), "The ≥6h spacing constraint is stated")
    }

    func testTwoADayPromptInstructsDropOnPoorReadiness() {
        let msg = DailyCoachPrompt.userMessage(for: picture(), plannedModality: "pull", plannedSecondary: "pool")
        XCTAssertTrue(msg.contains("DROP the second part"),
                      "The brain must be told it can drop the second session on poor readiness")
        XCTAssertTrue(msg.lowercased().contains("yellow"),
                      "The drop condition (yellow-or-worse) is stated")
    }

    func testPromptStatesTheCalendarWindows() {
        let msg = DailyCoachPrompt.userMessage(for: picture(), plannedModality: "push",
                                               plannedSecondary: "run", secondaryWindows: (8 * 60, 18 * 60))
        XCTAssertTrue(msg.contains("free windows"),
                      "When real calendar windows exist, the brain is told to place the parts there")
    }

    func testNoWindowHintWhenNoneProvided() {
        let msg = DailyCoachPrompt.userMessage(for: picture(), plannedModality: "push", plannedSecondary: "run")
        XCTAssertTrue(msg.contains("TWO-A-DAY"))
        XCTAssertFalse(msg.contains("free windows"), "No calendar data → no window hint, just the ≥6h rule")
    }

    func testSingleSessionPromptHasNoTwoADayLine() {
        let msg = DailyCoachPrompt.userMessage(for: picture(), plannedModality: "push", plannedSecondary: nil)
        XCTAssertTrue(msg.contains("TODAY'S PLANNED SESSION: push"),
                      "A plain planned session still gets its keep-the-modality line")
        XCTAssertFalse(msg.contains("TWO-A-DAY"),
                       "A single-session day must not mention a two-a-day")
    }

    func testNoPlanNoPlannedLineAtAll() {
        // Cold-start: no plan yet → neither a planned nor a two-a-day line.
        let msg = DailyCoachPrompt.userMessage(for: picture(), plannedModality: nil, plannedSecondary: "run")
        XCTAssertFalse(msg.contains("TWO-A-DAY"),
                       "Without a planned modality there is no planned session to attach a second to")
        XCTAssertFalse(msg.contains("TODAY'S PLANNED SESSION"))
    }
}
