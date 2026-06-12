//
// VenuePatternTests.swift
// Tempo
//
// Proves the §16 venue/pattern learning core: median + modal-venue math, the
// ≥3-sample cold-start gate, the §15.2 completion-rate exclusions (floor-forced
// and venue-unavailable skips are NOT user flakes), confirmation-overrides-
// inference priority in sample building, the §16.3 honesty tiers, and the
// venue line the DailyCoachPrompt CONTEXT block renders. Pure math + sample
// building are tested without SwiftData persistence (models are constructed
// standalone, the same pattern the engine tests use).
//

@testable import Tempo
import XCTest

final class VenuePatternTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")! // Nicola is in Miami (ET)
        return c
    }()

    /// Tuesday 2023-11-14 as the fixed anchor; offsets in WEEKS keep every
    /// generated date on the same weekday, which is the learner's key.
    private func anchor(weeksAgo: Int, hour: Int = 16, minute: Int = 0) -> Date {
        let base = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 (Tue)
        let day = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: cal.startOfDay(for: base))!
        return cal.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
    }

    private var tuesday: Int { cal.component(.weekday, from: anchor(weeksAgo: 0)) }

    private func sample(
        weeksAgo: Int, hour: Int = 16, minute: Int = 0,
        startMin: Int? = nil, durationMin: Int? = nil,
        venue: TrainingVenue? = .gym, completed: Bool = true, prescribed: Bool = true
    ) -> VenueSample {
        VenueSample(
            date: anchor(weeksAgo: weeksAgo, hour: hour, minute: minute),
            startMin: startMin, durationMin: durationMin,
            venue: venue, completed: completed, prescribed: prescribed
        )
    }

    // MARK: - Math: median + modal venue

    func testMedianPicksLowerMiddleObservedValue() {
        XCTAssertEqual(VenuePatternMath.median([240, 960, 965, 970]), 960, "Even count → lower-middle real value, no interpolation")
        XCTAssertEqual(VenuePatternMath.median([965, 960, 970]), 965)
        XCTAssertNil(VenuePatternMath.median([]))
    }

    func testModalVenueTieBreaksToMostRecent() {
        // 2× gym (older), 2× field (one is the most recent) → field wins:
        // habit drift beats enum order.
        let samples = [
            sample(weeksAgo: 4, venue: .gym),
            sample(weeksAgo: 3, venue: .gym),
            sample(weeksAgo: 2, venue: .field),
            sample(weeksAgo: 1, venue: .field),
        ]
        XCTAssertEqual(VenuePatternMath.modalVenue(of: samples), .field)
    }

    // MARK: - Snapshot: cold-start gate + completion rate

    func testColdStartUnderThreeSamplesNoSnapshot() {
        let samples = [sample(weeksAgo: 1), sample(weeksAgo: 2)]
        XCTAssertNil(
            VenuePatternMath.snapshot(samples: samples, weekday: tuesday, calendar: cal),
            "§16.2 — under 3 completed samples there is NO proposal"
        )
    }

    func testSnapshotSummarizesEstablishedWeekday() {
        let samples = [
            sample(weeksAgo: 1, startMin: 965, durationMin: 50),
            sample(weeksAgo: 2, startMin: 960, durationMin: 48),
            sample(weeksAgo: 3, startMin: 970, durationMin: 55),
        ]
        let snap = try! XCTUnwrap(VenuePatternMath.snapshot(samples: samples, weekday: tuesday, calendar: cal))
        XCTAssertEqual(snap.venue, .gym)
        XCTAssertEqual(snap.medianStartMin, 965)
        XCTAssertEqual(snap.medianDurationMin, 50)
        XCTAssertEqual(snap.completionRate, 1.0)
        XCTAssertEqual(snap.sampleCount, 3)
        XCTAssertFalse(snap.assertsTime, "§16.3 — 3 samples is below the ≥5 assert-time tier")
    }

    func testCompletionRateCountsOnlyPrescribedAndUserFlakes() {
        // 3 completed prescribed + 1 user-flake skip + 1 Whoop-only extra
        // (not prescribed) → rate 3/4; the extra is venue/time evidence only.
        let samples = [
            sample(weeksAgo: 1), sample(weeksAgo: 2), sample(weeksAgo: 3),
            sample(weeksAgo: 4, venue: nil, completed: false, prescribed: true),
            sample(weeksAgo: 5, venue: .field, completed: true, prescribed: false),
        ]
        let snap = try! XCTUnwrap(VenuePatternMath.snapshot(samples: samples, weekday: tuesday, calendar: cal))
        XCTAssertEqual(snap.completionRate, 0.75, accuracy: 0.001)
        XCTAssertEqual(snap.sampleCount, 4, "Completed count includes the unprescribed extra")
    }

    func testAssertTimeTierAtFiveSamples() {
        let samples = (1 ... 5).map { sample(weeksAgo: $0, startMin: 960) }
        let snap = try! XCTUnwrap(VenuePatternMath.snapshot(samples: samples, weekday: tuesday, calendar: cal))
        XCTAssertTrue(snap.assertsTime, "§16.3 — ≥5 samples with a known time may assert 'usual 4PM'")
    }

    // MARK: - Sample building (learner evidence rules)

    func testFloorForcedSkipDoesNotEnterDenominator() {
        let floorSkip = makePlan(weeksAgo: 1, status: .skipped, skipReason: .floorForced)
        let venueSkip = makePlan(weeksAgo: 2, status: .skipped, skipReason: .venueUnavailable)
        let userSkip = makePlan(weeksAgo: 3, status: .skipped, skipReason: .userSkipped)
        let bareSkip = makePlan(weeksAgo: 4, status: .skipped, skipReason: nil)

        let samples = VenuePatternLearner.buildSamples(
            plans: [floorSkip, venueSkip, userSkip, bareSkip],
            activities: [], confirmations: [], calendar: cal
        )
        XCTAssertEqual(samples.count, 2, "§15.2 — only user flakes (explicit or bare) are evidence; floor/venue skips vanish")
        XCTAssertTrue(samples.allSatisfy { $0.prescribed && !$0.completed })
    }

    func testConfirmationOverridesInferredVenueForItsDay() {
        // A completed PULL plan infers gym; the user's confirmation that day
        // says home — the explicit answer wins, and no duplicate sample appears.
        let plan = makePlan(weeksAgo: 1, status: .completed)
        let confirmation = VenueConfirmation(
            dayKey: cal.startOfDay(for: anchor(weeksAgo: 1)), venue: .home, startMin: 900
        )
        let samples = VenuePatternLearner.buildSamples(
            plans: [plan], activities: [], confirmations: [confirmation], calendar: cal
        )
        XCTAssertEqual(samples.count, 1, "Confirmation must not double-count a completed-plan day")
        XCTAssertEqual(samples[0].venue, .home, "Explicit answer beats WorkoutType inference")
    }

    func testStandaloneConfirmationIsEvidence() {
        let confirmation = VenueConfirmation(
            dayKey: cal.startOfDay(for: anchor(weeksAgo: 1)), venue: .pool, startMin: 480
        )
        let samples = VenuePatternLearner.buildSamples(
            plans: [], activities: [], confirmations: [confirmation], calendar: cal
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].venue, .pool)
        XCTAssertEqual(samples[0].startMin, 480)
        XCTAssertFalse(samples[0].prescribed, "An answer is not a prescription — stays out of the completion rate")
    }

    func testPlannedAndInProgressAreNotEvidence() {
        let pending = makePlan(weeksAgo: 0, status: .planned)
        let live = makePlan(weeksAgo: 0, status: .inProgress)
        let samples = VenuePatternLearner.buildSamples(
            plans: [pending, live], activities: [], confirmations: [], calendar: cal
        )
        XCTAssertTrue(samples.isEmpty, "Unresolved days must not read as skips")
    }

    // MARK: - Venue inference

    func testWorkoutTypeVenueInference() {
        XCTAssertEqual(WorkoutType.pull.inferredVenue, .gym)
        XCTAssertEqual(WorkoutType.sprint.inferredVenue, .field)
        XCTAssertEqual(WorkoutType.run.inferredVenue, .outdoor)
        XCTAssertEqual(WorkoutType.mobility.inferredVenue, .home)
        XCTAssertNil(WorkoutType.rest.inferredVenue)
    }

    // MARK: - Prompt seam (CONTEXT venue line)

    func testPromptRendersConfirmedVenueAsFact() {
        let venue = VenueTodaySnapshot(venueRaw: "gym", startMin: 965, durationMin: 50, confirmed: true, assertsTime: true)
        let picture = ReadinessAssembler.assemble(history: [], today: nil, venueToday: venue)
        let message = DailyCoachPrompt.userMessage(for: picture)
        XCTAssertTrue(message.contains("- Venue today: gym at 16:05, ~50 min (user-confirmed)."))
    }

    func testPromptRendersEstablishedPatternWithTime() {
        let venue = VenueTodaySnapshot(venueRaw: "gym", startMin: 960, durationMin: nil, confirmed: false, assertsTime: true)
        let picture = ReadinessAssembler.assemble(history: [], today: nil, venueToday: venue)
        let message = DailyCoachPrompt.userMessage(for: picture)
        XCTAssertTrue(message.contains("- Venue today (usual pattern): gym around 16:00."))
    }

    func testPromptRendersEarlyPatternSoft() {
        let venue = VenueTodaySnapshot(venueRaw: "field", startMin: nil, durationMin: nil, confirmed: false, assertsTime: false)
        let picture = ReadinessAssembler.assemble(history: [], today: nil, venueToday: venue)
        let message = DailyCoachPrompt.userMessage(for: picture)
        XCTAssertTrue(message.contains("- Venue today (early pattern, low confidence): likely field."))
    }

    func testPromptSilentWithoutVenueContext() {
        let picture = ReadinessAssembler.assemble(history: [], today: nil)
        XCTAssertFalse(
            DailyCoachPrompt.userMessage(for: picture).contains("Venue today"),
            "Cold-start honesty — no venue line below the gate"
        )
    }

    // MARK: - Helpers

    private func makePlan(weeksAgo: Int, status: WorkoutStatus, skipReason: SkipReason? = nil) -> WorkoutPlan {
        let plan = WorkoutPlan(date: anchor(weeksAgo: weeksAgo), type: .pull)
        plan.status = status
        plan.skipReason = skipReason
        if status == .completed {
            plan.startedAt = anchor(weeksAgo: weeksAgo, hour: 16, minute: 5)
            plan.finishedAt = anchor(weeksAgo: weeksAgo, hour: 16, minute: 55)
        }
        return plan
    }
}
