//
// LearnedPreference.swift
// Tempo
//
// Created by Tempo on 20/05/2026.
//
// Versioned, source-attributed, decayable, contradictable preference store
// for the Coach agent. Per `.plans/coach-agent-findings.md` (v2): the agent
// reasons over learned preferences instead of hardcoded life-OS rules,
// adapting to any user's actual habits over time.

import Foundation
import SwiftData

// MARK: - LearnedPreference

@Model
final class LearnedPreference {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Claim

    /// Human-readable preference text the agent reads + cites.
    /// Example: "Nicola prefers dinner before 9pm on weekdays."
    var text: String

    /// Dotted taxonomy path used for relevance retrieval.
    /// Example: "meal_timing.dinner" — see `Subjects` enum for canonical paths.
    var subject: String

    /// 0.0–1.0. Decays over time when not reinforced; reinforced on
    /// observed behaviour or repeat explicit mentions.
    var confidence: Double

    // MARK: - Provenance

    /// `Source` raw value. Stored as String per SwiftData convention
    /// (SwiftData doesn't support enum-with-rawValue natively on stored props).
    var sourceRaw: String

    /// Optional conversation ID that produced this preference (if extracted).
    var sourceConversationID: UUID?

    /// Optional turn index within the source conversation.
    var sourceTurnIndex: Int?

    // MARK: - Lifecycle

    /// Number of independent reinforcements observed. Increments when the
    /// extractor sees the same claim again or the behaviour observer
    /// confirms it.
    var evidenceCount: Int

    var firstSeenAt: Date

    /// Updated on every reinforcement. Drives recency-weighted retrieval
    /// and decay.
    var lastSeenAt: Date

    /// ID of a newer preference that supersedes this one. Non-nil = leaf
    /// (most recent) is the truth; this row is kept for audit but never
    /// surfaced to the agent.
    var contradictedByID: UUID?

    /// Timestamp of when supersession happened. Audit only.
    var supersededAt: Date?

    /// Soft delete. Excluded from agent context. Surfaced in the memory UI
    /// as "stale, tap to re-confirm."
    var isActive: Bool

    /// User saw + confirmed this in the Coach Memory screen. Bumps source
    /// to `.userVerified` and makes it immune to decay until contradicted.
    var userVerified: Bool

    // MARK: - Computed

    @Transient
    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .inferred }
        set { sourceRaw = newValue.rawValue }
    }

    /// True when this preference should be loaded into agent context.
    /// Excludes soft-deleted, superseded, and below-floor-confidence rows.
    @Transient
    var isRetrievable: Bool {
        isActive && contradictedByID == nil && confidence >= 0.2
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        text: String,
        subject: String,
        confidence: Double,
        source: Source,
        evidenceCount: Int = 1,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        contradictedByID: UUID? = nil,
        supersededAt: Date? = nil,
        isActive: Bool = true,
        userVerified: Bool = false,
        sourceConversationID: UUID? = nil,
        sourceTurnIndex: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.subject = subject
        self.confidence = max(0.0, min(1.0, confidence))
        sourceRaw = source.rawValue
        self.evidenceCount = evidenceCount
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.contradictedByID = contradictedByID
        self.supersededAt = supersededAt
        self.isActive = isActive
        self.userVerified = userVerified
        self.sourceConversationID = sourceConversationID
        self.sourceTurnIndex = sourceTurnIndex
    }
}

// MARK: - Source

extension LearnedPreference {
    /// How the preference was learned. Each source has different trust
    /// weight and decay behaviour:
    /// - `.explicit`: user said it in a conversation. Standard decay.
    /// - `.observed`: behaviour-observer extracted from planned-vs-actual
    ///   data. Slightly faster decay (0.97/day vs 0.99/day).
    /// - `.inferred`: agent guessed from one-off context. Same decay as
    ///   observed; needs reinforcement to stick.
    /// - `.userVerified`: user opened the Coach Memory screen and
    ///   confirmed (or manually added). Immune to decay until contradicted.
    enum Source: String, Codable, CaseIterable {
        case explicit
        case observed
        case inferred
        case userVerified
    }
}

// MARK: - Action (used by updatePreference tool)

extension LearnedPreference {
    /// Mutations the agent can perform on an existing preference via the
    /// `updatePreference` tool. The agent never writes raw fields — it
    /// expresses intent through these actions and the tool applies the
    /// correct state transition.
    enum Action: String, Codable {
        /// Mark this preference as overridden by a newer one. The new
        /// preference is created separately (via `recordPreference`); this
        /// action wires the supersession edge.
        case supersede

        /// Keep the preference but narrow its scope. The new text describes
        /// the narrower claim (e.g. "weekdays only"). Bumps `userVerified`.
        case keepClarifyScope

        /// Soft-delete. The user said this preference is wrong / no longer
        /// true. Excluded from agent context permanently.
        case deactivate

        /// The most recent observation that looked like reinforcement was
        /// actually a one-off. Decrement evidence + lower confidence.
        case markOneOff
    }
}

// MARK: - Subjects (canonical taxonomy)

/// Suggested subject paths for the agent + extractor. Soft taxonomy —
/// extraction can coin new subjects; these are seeds for the prompt and
/// for behaviour-observer outputs. Add to this list as patterns emerge.
enum LearnedPreferenceSubject {
    // Meal timing — when food happens
    static let mealTimingBreakfast = "meal_timing.breakfast"
    static let mealTimingLunch = "meal_timing.lunch"
    static let mealTimingDinner = "meal_timing.dinner"
    static let mealTimingSnack = "meal_timing.snack"

    // Meal content — what food
    static let mealContentCuisine = "meal_content.cuisine"
    static let mealContentDisliked = "meal_content.ingredients.disliked"
    static let mealContentPrepSpeed = "meal_content.prep_speed"

    // Training — when, intensity, recovery
    static let trainingIntensity = "training.intensity"
    static let trainingTimingPreferred = "training.timing.preferred"
    static let trainingRecoveryTolerance = "training.recovery.tolerance"

    // Sleep & wake
    static let sleepBedtime = "sleep.bedtime"
    static let sleepWake = "sleep.wake"
    static let sleepWeekendDrift = "sleep.weekend_drift"

    // Social
    static let socialWeekday = "social.weekday"
    static let socialWeekend = "social.weekend"
    static let socialMatchDays = "social.match_days"

    // Study + work
    static let studyPeakHours = "study.peak_hours"
    static let studySessionLength = "study.session_length"
    static let workPeakHours = "work.peak_hours"
    static let workSchedule = "work.schedule"

    // Digestion / physiology
    static let digestionBeforeBed = "digestion.before_bed"
    static let digestionBeforeTraining = "digestion.before_training"

    // Mood / recovery patterns
    static let moodWeeklyPattern = "mood.weekly_pattern"
    static let recoveryStrainTolerance = "recovery.tolerance.strain"
    static let recoverySleepDebtTolerance = "recovery.tolerance.sleep_debt"

    // Communication preferences
    static let generalCommunicationStyle = "general.communication_style"
    static let generalCoachingTone = "general.coaching_tone"
}

// MARK: - Mutation helpers

extension LearnedPreference {
    /// Reinforce on observation or repeat mention. Increments evidence,
    /// bumps confidence (capped at 1.0), updates lastSeenAt. Does nothing
    /// to a verified preference's confidence since it's already at 1.0.
    func markReinforced(by amount: Double = 0.05, at date: Date = Date()) {
        evidenceCount += 1
        lastSeenAt = date
        if !userVerified {
            confidence = min(1.0, confidence + amount)
        }
    }

    /// Wire this preference as superseded by a newer one. Both rows stay in
    /// the store for audit; only the newer one is retrievable.
    func supersede(by newerID: UUID, at date: Date = Date()) {
        contradictedByID = newerID
        supersededAt = date
    }

    /// Soft delete. Used by `Action.deactivate` and by the decay job when
    /// confidence falls below the floor.
    func deactivate(at date: Date = Date()) {
        isActive = false
        lastSeenAt = date
    }

    /// User opened the memory UI and confirmed. Promotes source, locks
    /// confidence at 1.0, future decay is no-op.
    func markUserVerified(at date: Date = Date()) {
        source = .userVerified
        userVerified = true
        confidence = 1.0
        lastSeenAt = date
    }

    /// Apply per-day exponential decay. Run nightly by the behaviour
    /// observer. Verified preferences are immune. Explicit decays slower
    /// (0.99/day, ~70-day half-life) than observed/inferred (0.97/day,
    /// ~23-day half-life) since explicit statements should be more durable.
    func applyDailyDecay(at date: Date = Date()) {
        guard !userVerified else { return }
        // Skip decay if we just saw evidence today.
        let cal = Calendar.current
        if cal.isDate(lastSeenAt, inSameDayAs: date) { return }
        let factor: Double
        switch source {
        case .explicit, .userVerified: factor = 0.99
        case .observed, .inferred: factor = 0.97
        }
        confidence *= factor
        if confidence < 0.2 {
            deactivate(at: date)
        }
    }
}
