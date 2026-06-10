//
// VenuePattern.swift
// Tempo
//
// Venue & pattern learning (docs/INTELLIGENT_TRAINING_SYSTEM.md §16, Decisions
// #6/#9): the "you usually hit the gym ~4PM, can you make it?" feature. Learns,
// per weekday, the typical venue / start time / duration / completion rate from
// the last ~8 weeks of real sessions, and records the morning propose-confirm
// answers so the pattern converges on EXPLICIT venue data over time.
//
// The venue data-source honesty (decided 2026-06-09): nothing in the codebase
// recorded venue before this file. Start time, duration and completion come
// from real session data (WorkoutPlan.startedAt/actualDurationMinutes/status,
// ActivitySession.startTime/durationMinutes); venue is INFERRED from the
// session's WorkoutType (push→gym, sprint→field, …) until confirmed answers
// (VenueConfirmation) accrue — those take priority for their day.
//
// Cold-start (§16.2): under 3 completed samples for a weekday there is NO
// proposal. Under 5, the proposal phrases soft ("Gym today?"); at ≥5 it may
// assert the time ("your usual 4PM?") — §16.3 honesty tiers.
//
// All fields additive per the single-V1-schema migration rule (§10).
//

import Foundation
import SwiftData

// MARK: - TrainingVenue

/// Where a session happens (§16.1: gym/field/pool/home; outdoor covers runs).
enum TrainingVenue: String, Codable, Sendable, CaseIterable {
    case gym
    case field
    case pool
    case home
    case outdoor

    var displayName: String {
        switch self {
        case .gym: "Gym"
        case .field: "Field"
        case .pool: "Pool"
        case .home: "Home"
        case .outdoor: "Outdoor"
        }
    }
}

extension WorkoutType {
    /// The venue a session of this type implies, used as the seed signal until
    /// explicit VenueConfirmation answers accrue (the §16 bootstrap decision).
    var inferredVenue: TrainingVenue? {
        switch self {
        case .push, .pull, .legs, .upper, .lower, .fullBody: .gym
        case .football, .sprint, .conditioning: .field
        case .run: .outdoor
        case .pool: .pool
        case .mobility: .home
        case .rest: nil
        }
    }
}

// MARK: - VenuePattern (learned, one row per weekday)

/// The learned pattern for one weekday. Recomputed (not incrementally mutated)
/// from the trailing window on every session save — rows are derived data and
/// can always be rebuilt.
@Model
final class VenuePattern {
    /// `Calendar.component(.weekday)` convention: 1 = Sunday … 7 = Saturday.
    var weekday: Int

    /// Mode of the venue evidence (confirmed > inferred). nil = no venue signal.
    var venueRaw: String?

    /// Rolling median of confirmed/actual start times, minutes after midnight.
    var medianStartMin: Int?

    /// Rolling median of ACTUAL durations (Nicola's sessions run ~50min, not
    /// the prescribed 60 — §16.1).
    var medianDurationMin: Int?

    /// Fraction of prescribed sessions on this weekday actually completed.
    /// Floor-forced / venue-unavailable skips are excluded from the
    /// denominator (§15.2 — not user failures).
    var completionRate: Double

    /// Completed-sample count backing this row (drives the §16.3 honesty tiers).
    var sampleCount: Int

    var updatedAt: Date

    init(
        weekday: Int,
        venueRaw: String? = nil,
        medianStartMin: Int? = nil,
        medianDurationMin: Int? = nil,
        completionRate: Double = 1.0,
        sampleCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.weekday = weekday
        self.venueRaw = venueRaw
        self.medianStartMin = medianStartMin
        self.medianDurationMin = medianDurationMin
        self.completionRate = completionRate
        self.sampleCount = sampleCount
        self.updatedAt = updatedAt
    }

    @Transient
    var venue: TrainingVenue? {
        venueRaw.flatMap(TrainingVenue.init(rawValue:))
    }
}

// MARK: - VenueConfirmation (one per day — the propose-confirm answer)

/// The user's answer to the morning venue proposal ("usual 4PM?" → Yes/Change).
/// Feeds today's prescription (DailyCoachPrompt venue line) AND becomes the
/// highest-quality learning sample for its day (§16.2).
@Model
final class VenueConfirmation {
    @Attribute(.unique)
    var id: UUID

    /// Start-of-day of the day this answer is for.
    var dayKey: Date

    var venueRaw: String

    /// Confirmed start time, minutes after midnight. nil = venue-only answer.
    var startMin: Int?

    var createdAt: Date

    init(dayKey: Date, venue: TrainingVenue, startMin: Int? = nil, createdAt: Date = Date()) {
        id = UUID()
        self.dayKey = dayKey
        venueRaw = venue.rawValue
        self.startMin = startMin
        self.createdAt = createdAt
    }

    @Transient
    var venue: TrainingVenue {
        TrainingVenue(rawValue: venueRaw) ?? .home
    }
}

// MARK: - Pure pattern math (testable, no SwiftData / no Date.now in core)

/// One unit of evidence for the learner. Built from WorkoutPlans (prescribed),
/// unlinked ActivitySessions (Whoop-detected, not prescribed) and
/// VenueConfirmations (explicit answers) by VenuePatternLearner.
struct VenueSample: Equatable, Sendable {
    let date: Date
    /// Minutes after local midnight, when known.
    let startMin: Int?
    let durationMin: Int?
    let venue: TrainingVenue?
    /// Did training actually happen.
    let completed: Bool
    /// Was this a prescribed session — only prescribed samples enter the
    /// completion-rate denominator (Whoop-detected extras don't).
    let prescribed: Bool
}

/// The learned summary for one weekday — what VenuePattern rows persist and
/// the proposal card / prompt read.
struct VenuePatternSnapshot: Equatable, Sendable {
    let weekday: Int
    let venue: TrainingVenue?
    let medianStartMin: Int?
    let medianDurationMin: Int?
    let completionRate: Double
    let sampleCount: Int

    /// §16.3 — only an established pattern (≥5 samples) asserts the time
    /// ("your usual 4PM?"); below that the proposal phrases soft ("Gym today?").
    var assertsTime: Bool { sampleCount >= 5 && medianStartMin != nil }
}

enum VenuePatternMath {
    /// §16.2 cold-start: no proposal until this many completed samples accrue.
    static let minSamplesForProposal = 3
    /// §16.3: assert the usual time only at/after this many samples.
    static let minSamplesToAssertTime = 5

    /// Summarize one weekday's evidence, or nil under the cold-start gate.
    static func snapshot(
        samples: [VenueSample],
        weekday: Int,
        calendar: Calendar = .current
    ) -> VenuePatternSnapshot? {
        let dayDated = samples.filter { calendar.component(.weekday, from: $0.date) == weekday }
        let done = dayDated.filter(\.completed)
        guard done.count >= minSamplesForProposal else { return nil }

        let prescribed = dayDated.filter(\.prescribed)
        let rate = prescribed.isEmpty
            ? 1.0
            : Double(prescribed.filter(\.completed).count) / Double(prescribed.count)

        return VenuePatternSnapshot(
            weekday: weekday,
            venue: modalVenue(of: done),
            medianStartMin: median(done.compactMap(\.startMin)),
            medianDurationMin: median(done.compactMap(\.durationMin)),
            completionRate: rate,
            sampleCount: done.count
        )
    }

    /// Most frequent venue; ties resolve to the most RECENT sample's venue
    /// among the tied candidates (habit drift should win, not enum order).
    static func modalVenue(of samples: [VenueSample]) -> TrainingVenue? {
        let dated = samples.compactMap { s in s.venue.map { (venue: $0, date: s.date) } }
        guard !dated.isEmpty else { return nil }
        var counts: [TrainingVenue: Int] = [:]
        for entry in dated { counts[entry.venue, default: 0] += 1 }
        let top = counts.values.max() ?? 0
        let tied = Set(counts.filter { $0.value == top }.map(\.key))
        return dated.filter { tied.contains($0.venue) }.max { $0.date < $1.date }?.venue
    }

    /// Standard median (lower-middle for even counts — a real observed value
    /// beats an interpolated 16:32½ that never happened).
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }

    /// "16:05"-style clock label for a minutes-after-midnight value.
    static func clockLabel(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
