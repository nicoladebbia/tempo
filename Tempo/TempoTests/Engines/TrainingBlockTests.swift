//
// TrainingBlockTests.swift
// Tempo
//
// Proves the pure training-block math (docs/INTELLIGENT_TRAINING_SYSTEM.md
// §14 Decision 1): currentEmphasis picks the block covering today with both
// boundary days inclusive, resolves overlaps latest-start-wins, and returns
// nil when nothing covers today (callers default to .physique — the pre-D3
// behavior). Also pins the two prompt/goal seams the block feeds: the
// DailyCoachPrompt CONTEXT line and BlockEmphasis.weeklyGoal — the physique
// goal MUST stay the pre-D3 "hypertrophy" literal so an untouched install's
// weekly prompt is byte-identical. Pure — no SwiftData, no implicit "now".
//

@testable import Tempo
import XCTest

final class TrainingBlockTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")! // Nicola is in Miami (ET)
        return c
    }()

    /// A fixed reference day at noon so ±hours never crosses a day boundary.
    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        let start = cal.startOfDay(for: base)
        let shifted = cal.date(byAdding: .day, value: offset, to: start)!
        return cal.date(byAdding: .hour, value: hour, to: shifted)!
    }

    private func span(_ emphasis: BlockEmphasis, start: Int, end: Int? = nil) -> BlockSpan {
        BlockSpan(emphasis: emphasis, start: day(start), end: end.map { day($0) })
    }

    // MARK: - currentEmphasis selection

    func testNoBlocksReturnsNil() {
        XCTAssertNil(TrainingBlockSchedule.currentEmphasis(spans: [], on: day(0), calendar: cal))
    }

    func testOpenEndedBlockCoversToday() {
        let spans = [span(.soccer, start: -10)]
        XCTAssertEqual(TrainingBlockSchedule.currentEmphasis(spans: spans, on: day(0), calendar: cal), .soccer)
    }

    func testEndedBlockNoLongerApplies() {
        let spans = [span(.soccer, start: -10, end: -3)]
        XCTAssertNil(TrainingBlockSchedule.currentEmphasis(spans: spans, on: day(0), calendar: cal))
    }

    func testFutureBlockDoesNotApplyYet() {
        let spans = [span(.soccer, start: 2)]
        XCTAssertNil(TrainingBlockSchedule.currentEmphasis(spans: spans, on: day(0), calendar: cal))
    }

    func testStartDayIsInclusive() {
        // Block starts today at 9AM, asked at 8AM same day — start-of-day math
        // means the block already applies (a block is a DAY-granular thing).
        let spans = [BlockSpan(emphasis: .soccer, start: day(0, hour: 9), end: nil)]
        XCTAssertEqual(
            TrainingBlockSchedule.currentEmphasis(spans: spans, on: day(0, hour: 8), calendar: cal),
            .soccer
        )
    }

    func testEndDayIsInclusive() {
        // endDate IS the last covered day — still active on it, gone the day after.
        let spans = [span(.soccer, start: -5, end: 0)]
        XCTAssertEqual(TrainingBlockSchedule.currentEmphasis(spans: spans, on: day(0), calendar: cal), .soccer)
        XCTAssertNil(TrainingBlockSchedule.currentEmphasis(spans: spans, on: day(1), calendar: cal))
    }

    func testOverlapResolvesLatestStartWins() {
        // An old open-ended physique block + a soccer block declared later:
        // the newer declaration supersedes without the old needing closure.
        let spans = [span(.physique, start: -30), span(.soccer, start: -2)]
        XCTAssertEqual(TrainingBlockSchedule.currentEmphasis(spans: spans, on: day(0), calendar: cal), .soccer)
    }

    func testRevertingAfterClosedBlockFallsThrough() {
        // Soccer block ended yesterday; the older open-ended physique block
        // is still in force underneath it.
        let spans = [span(.physique, start: -30), span(.soccer, start: -10, end: -1)]
        XCTAssertEqual(TrainingBlockSchedule.currentEmphasis(spans: spans, on: day(0), calendar: cal), .physique)
    }

    // MARK: - Prompt seam (DailyCoachPrompt CONTEXT line)

    func testPromptCarriesDeclaredEmphasis() {
        // Assembled through the real assembler param, proving the pass-through.
        let picture = ReadinessAssembler.assemble(history: [], today: nil, blockEmphasis: .soccer)
        let message = DailyCoachPrompt.userMessage(for: picture)
        XCTAssertTrue(message.contains("- Block emphasis: soccer."))
        XCTAssertFalse(message.contains("(default)"))
    }

    func testPromptDefaultsToPhysiqueLineWhenNoBlockSet() {
        // nil emphasis → the pre-D3 line VERBATIM, so the calibrated prompt
        // (harness 23/23) is unchanged for an untouched install.
        let picture = ReadinessAssembler.assemble(history: [], today: nil)
        let message = DailyCoachPrompt.userMessage(for: picture)
        XCTAssertTrue(message.contains("- Block emphasis: physique (default)."))
    }

    // MARK: - Weekly-goal seam (AIProgramPlanner goal:)

    func testPhysiqueWeeklyGoalIsPreD3Literal() {
        XCTAssertEqual(BlockEmphasis.physique.weeklyGoal, "hypertrophy")
    }

    func testSoccerWeeklyGoalNamesBothGoals() {
        let goal = BlockEmphasis.soccer.weeklyGoal
        XCTAssertTrue(goal.contains("soccer"))
        XCTAssertTrue(goal.contains("maintenance"))
    }
}
