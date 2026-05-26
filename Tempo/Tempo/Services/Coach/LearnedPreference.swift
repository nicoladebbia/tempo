//
// LearnedPreference.swift
// Tempo
//
// Coach v2.1 Phase 2 — the memory layer.
//
// One row per thing Coach knows about the user. Source-attributed,
// confidence-scored, scoped, polarity-tagged, decayable, contradictable,
// user-verifiable.
//
// Per .plans/coach-v2.1/02-data-model.md.
//

import Foundation
import SwiftData

// MARK: - LearnedPreference

@Model
final class LearnedPreference {
    @Attribute(.unique)
    var id: UUID

    /// The preference itself, as plain English ("user needs 2.5h between
    /// dinner and sleep"). Third-person; surfaced verbatim to the agent.
    var text: String

    /// Taxonomy path (dot-separated). Examples:
    ///   - `digestion.before_bed`
    ///   - `training.match_days`
    ///   - `meal_timing.breakfast.actual`
    ///   - `dislikes.food.raisins`
    ///   - `tone.style`
    /// Extractor can coin new paths; curation is a manual quarterly task.
    var subject: String

    /// Stored raw value of `Source`. Access via `source` computed accessor.
    var sourceRaw: String

    /// Stored raw value of `Polarity`. Access via `polarity` computed accessor.
    var polarityRaw: String

    /// Stored raw value of `Scope`. Access via `scope` computed accessor.
    var scopeRaw: String

    /// 0.0–1.0 confidence. Defaults follow source on creation:
    ///   - explicit / userVerified: 0.9
    ///   - observed: 0.5
    ///   - inferred: 0.4
    /// Reinforcement bumps +0.05 capped at 1.0. Decay multiplies by
    /// `decayRate` per day until next reinforce.
    var confidence: Double

    /// Per-day decay multiplier. Set on creation based on subject.
    ///   - red_lines.* / goals.*: 1.0 (never decay)
    ///   - digestion.*: 0.99
    ///   - meal_timing.*: 0.98
    ///   - meal_prefs.* / dislikes.food.*: 0.97 / 0.98
    ///   - training.*: 0.97
    ///   - sleep.*: 0.96
    ///   - schedule.*: 0.95
    ///   - tone.*: 0.99
    /// Default 0.99 when subject doesn't match a known prefix.
    var decayRate: Double

    /// Times this preference has been reinforced. Floor 1 on creation.
    var evidenceCount: Int

    /// Last time observer/extractor saw evidence. Drives decay calc.
    var lastSeenAt: Date

    /// When the preference was first written.
    var createdAt: Date

    /// Set by Preference Health Daily Check when behavior contradicts.
    /// Agent surfaces in next chat via askUser.
    var needsReview: Bool

    /// Soft-delete flag. Below-floor confidence or user-deleted → false.
    /// Retriever filters out inactive rows.
    var isActive: Bool

    // MARK: - Provenance (optional)

    /// If extracted from a chat, which conversation. For traceability.
    var evidenceConvId: UUID?

    /// If extracted from a chat, which turn (0-indexed).
    var evidenceTurnIndex: Int?

    /// If a newer preference replaces this one, ID of the replacement.
    /// Old row stays for audit; UI hides.
    var supersededBy: UUID?

    // MARK: - Computed accessors

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .inferred }
        set { sourceRaw = newValue.rawValue }
    }

    var polarity: Polarity {
        get { Polarity(rawValue: polarityRaw) ?? .positive }
        set { polarityRaw = newValue.rawValue }
    }

    var scope: Scope {
        get { Scope(rawValue: scopeRaw) ?? .always }
        set { scopeRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        text: String,
        subject: String,
        source: Source = .inferred,
        polarity: Polarity = .positive,
        scope: Scope = .always,
        confidence: Double? = nil,
        decayRate: Double? = nil,
        evidenceCount: Int = 1,
        lastSeenAt: Date = Date(),
        createdAt: Date = Date(),
        needsReview: Bool = false,
        isActive: Bool = true,
        evidenceConvId: UUID? = nil,
        evidenceTurnIndex: Int? = nil,
        supersededBy: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.subject = subject
        self.sourceRaw = source.rawValue
        self.polarityRaw = polarity.rawValue
        self.scopeRaw = scope.rawValue
        // Confidence defaults by source unless caller specified one.
        self.confidence = confidence ?? Self.defaultConfidence(for: source)
        // Decay rate inferred from subject prefix unless caller specified one.
        self.decayRate = decayRate ?? Self.defaultDecayRate(for: subject)
        self.evidenceCount = max(1, evidenceCount)
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.needsReview = needsReview
        self.isActive = isActive
        self.evidenceConvId = evidenceConvId
        self.evidenceTurnIndex = evidenceTurnIndex
        self.supersededBy = supersededBy
    }

    // MARK: - Lifecycle helpers

    /// Behavior matches this preference — bump confidence and evidence count.
    /// `lastSeenAt` advances to the supplied moment (defaults to now).
    /// userVerified rows are immune to reinforcement bumps (they're already
    /// at 1.0); we still advance lastSeenAt so decay won't fire on them.
    func markReinforced(at moment: Date = Date()) {
        evidenceCount += 1
        if source != .userVerified {
            confidence = min(1.0, confidence + 0.05)
        }
        lastSeenAt = moment
    }

    /// A newer preference replaces this one. The replacement is created
    /// separately; this row stays for audit but is hidden by retriever.
    func supersede(by newID: UUID) {
        supersededBy = newID
        isActive = false
    }

    /// Soft delete. Either user-initiated or auto-fire when confidence
    /// decays below 0.2.
    func deactivate() {
        isActive = false
    }

    /// User typed or accepted this in the memory editor. Lifts confidence
    /// to 1.0, locks source as .userVerified (immune to decay until
    /// explicitly contradicted), clears any pending review flag.
    func markUserVerified() {
        source = .userVerified
        confidence = 1.0
        needsReview = false
        lastSeenAt = Date()
    }

    /// Apply one day of decay. Auto-deactivates when below the 0.2 floor.
    /// `daysElapsed` lets the observer batch decay when it hasn't run
    /// for a few days (e.g. user offline). Default 1.
    ///
    /// userVerified rows do NOT decay (they're locked at 1.0 until the
    /// user explicitly contradicts them).
    func applyDailyDecay(daysElapsed: Int = 1) {
        guard daysElapsed > 0 else { return }
        guard source != .userVerified else { return }
        guard decayRate < 1.0 else { return }
        let factor = pow(decayRate, Double(daysElapsed))
        confidence = max(0.0, confidence * factor)
        if confidence < 0.2 {
            deactivate()
        }
    }

    // MARK: - Defaults

    /// Source-based initial confidence per data-model doc §"Fields".
    static func defaultConfidence(for source: Source) -> Double {
        switch source {
        case .explicit: return 0.9
        case .userVerified: return 1.0
        case .observed: return 0.5
        case .inferred: return 0.4
        }
    }

    /// Subject-prefix-based decay rate per data-model doc §"Decay defaults
    /// by subject". Conservative default for unknown prefixes is 0.99.
    static func defaultDecayRate(for subject: String) -> Double {
        let lower = subject.lowercased()
        // Never-decay categories: allergies, religion, hard goals, red lines.
        if lower.hasPrefix("red_lines.") { return 1.0 }
        if lower.hasPrefix("goals.") { return 1.0 }
        // Per-prefix rates.
        if lower.hasPrefix("digestion.") { return 0.99 }
        if lower.hasPrefix("meal_timing.") { return 0.98 }
        if lower.hasPrefix("meal_prefs.") { return 0.97 }
        if lower.hasPrefix("dislikes.food.") { return 0.98 }
        if lower.hasPrefix("training.") { return 0.97 }
        if lower.hasPrefix("sleep.") { return 0.96 }
        if lower.hasPrefix("schedule.") { return 0.95 }
        if lower.hasPrefix("tone.") { return 0.99 }
        return 0.99
    }
}

// MARK: - Enums (raw String → SwiftData storage)

extension LearnedPreference {
    /// Where the preference came from.
    enum Source: String, Codable, CaseIterable, Sendable {
        /// User stated a recurring pattern in chat ("I never eat before 11am").
        case explicit
        /// Behavior observer inferred from the last 7 days of data.
        case observed
        /// Extractor inferred from chat context (lower confidence than explicit).
        case inferred
        /// User typed or accepted in the memory editor / interview.
        /// Immune to decay until explicitly contradicted.
        case userVerified
    }

    /// Three flavors of memory. Hard avoids never get suggested.
    enum Polarity: String, Codable, CaseIterable, Sendable {
        case positive
        case negative
        case avoidAtAllCosts
    }

    /// When the preference applies. Retriever filters by today's scope
    /// before ranking. Memory UI groups by scope inside each polarity tab.
    enum Scope: String, Codable, CaseIterable, Sendable {
        case always
        case weekday
        case weekend
        case dayTypeHard
        case dayTypeRest
        case eventTravel
        case eventMatch
        case seasonalSummer
    }
}
