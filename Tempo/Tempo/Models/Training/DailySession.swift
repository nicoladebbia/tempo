//
// DailySession.swift
// Tempo
//
// The persisted daily prescription from the readiness brain (docs/INTELLIGENT_TRAINING_SYSTEM.md §5.3, §8).
// Linked 1:1 to today's WorkoutPlan — THE desync guard from the §8 cadence
// contract: WorkoutPlan stays the schedule/status/adherence record; DailySession
// holds the brain's prescription content (modality/intensity/blocks/why/cue +
// the per-modality expected* predictions). They are created and resolved
// together, never independently.
//
// Gym days still flow through the existing engine (the gym block is a POINTER);
// DailySession is what gives NON-gym days (pool/run/field/bodyweight) a place to
// persist content, since WorkoutPlan has only gym-shaped PlannedExercise rows.
//
// The block list is stored as the §13 DailySessionDTO JSON (camelCase wire
// format) so the persisted shape == the AI/parser/card shape — one source of truth.
//

import Foundation
import SwiftData

@Model
final class DailySession {
    @Attribute(.unique)
    var id: UUID

    /// Start-of-day this session is for. One per day.
    @Attribute(.unique)
    var date: Date

    /// The modality label (maps to WorkoutType via the §13.1 mapping).
    var modality: String

    /// recovery|easy|moderate|hard|max (SessionIntensity raw).
    var intensityRaw: String

    var durationMin: Int

    /// The §13 blocks, stored as DailySessionDTO JSON (the single canonical shape).
    var blocksJSON: String

    var shortWhy: String
    var fullWhy: String?

    /// The brain's predictions — scored by the outcome loop (§13.2).
    var expectedStrain: Double?
    var expectedSessionRPE: Int?

    /// The floor tier that produced this session (severe|moderate|normal) and
    /// whether the floor downgraded the brain's pick. For the card + audit.
    var floorTierRaw: String
    var wasDowngraded: Bool

    /// How this session was produced — for honesty in the card + debugging.
    /// brain = real Haiku; floorFallback = deterministic (offline/402/parse-fail);
    /// simple = cold-start deterministic (<30 days history).
    var sourceRaw: String

    /// §8 connect — the user declined the brain's modality move and kept the
    /// planned workout ("keep pool"). The card collapses to a one-liner and
    /// nothing re-applies the move that day. Only brain-CHOSEN moves are
    /// overridable; a SEVERE floor skip is the safety contract and stays
    /// locked. Defaulted → auto-migrates.
    var userOverrode: Bool = false

    /// §14 #3 — the user's one-tap actual session RPE, DENORMALIZED off the
    /// linked WorkoutPlan at record time. sessionRPEAccuracy reads THIS, not
    /// `workoutPlan?.sessionRPE`: the 1:1 link is a one-way `.nullify` with no
    /// inverse, so a history-delete of the WorkoutPlan leaves this relationship
    /// dangling and traversing it crashes (invalidated backing). Reading the
    /// denormalized copy is crash-proof regardless of the plan's fate.
    /// Defaulted → auto-migrates; nil for sessions recorded before this field.
    var actualSessionRPE: Int? = nil

    var createdAt: Date

    // MARK: - 1:1 link to the day's WorkoutPlan (§8 desync guard)

    /// The schedule/status/adherence record this prescription belongs to. 1:1.
    @Relationship(deleteRule: .nullify)
    var workoutPlan: WorkoutPlan?

    init(
        date: Date,
        modality: String,
        intensity: SessionIntensity,
        durationMin: Int,
        blocksJSON: String,
        shortWhy: String,
        fullWhy: String? = nil,
        expectedStrain: Double? = nil,
        expectedSessionRPE: Int? = nil,
        floorTier: FloorTier,
        wasDowngraded: Bool,
        source: DailySessionSource,
        workoutPlan: WorkoutPlan? = nil,
        createdAt: Date = Date()
    ) {
        id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.modality = modality
        intensityRaw = intensity.rawValue
        self.durationMin = durationMin
        self.blocksJSON = blocksJSON
        self.shortWhy = shortWhy
        self.fullWhy = fullWhy
        self.expectedStrain = expectedStrain
        self.expectedSessionRPE = expectedSessionRPE
        floorTierRaw = floorTier.rawValue
        self.wasDowngraded = wasDowngraded
        sourceRaw = source.rawValue
        self.workoutPlan = workoutPlan
        self.createdAt = createdAt
    }

    // MARK: - Computed

    @Transient
    var intensity: SessionIntensity { SessionIntensity(rawValue: intensityRaw) ?? .moderate }

    @Transient
    var floorTier: FloorTier { FloorTier(rawValue: floorTierRaw) ?? .normal }

    @Transient
    var source: DailySessionSource { DailySessionSource(rawValue: sourceRaw) ?? .brain }

    /// Decoded blocks (the §13 wire shape). Empty on malformed JSON — never crashes.
    @Transient
    var blocks: [SessionBlockDTO] {
        guard let data = blocksJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SessionBlockDTO].self, from: data)
        else { return [] }
        return decoded
    }

    // MARK: - Factory from a (floor-applied) DailySessionDTO

    /// Builds + persists from the floor decision. Encodes the DTO's blocks to JSON.
    static func from(
        decision: FloorDecision,
        date: Date,
        source: DailySessionSource,
        workoutPlan: WorkoutPlan?
    ) -> DailySession {
        let dto = decision.session
        let json = (try? JSONEncoder().encode(dto.blocks)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return DailySession(
            date: date,
            modality: dto.modality,
            intensity: dto.intensity,
            durationMin: dto.durationMin,
            blocksJSON: json,
            shortWhy: dto.shortWhy,
            fullWhy: dto.fullWhy,
            expectedStrain: dto.expectedStrain,
            expectedSessionRPE: dto.expectedSessionRPE,
            floorTier: decision.tier,
            wasDowngraded: decision.wasDowngraded,
            source: source,
            workoutPlan: workoutPlan
        )
    }
}

// MARK: - Source provenance

enum DailySessionSource: String, Codable, Sendable {
    /// Real Haiku brain call.
    case brain
    /// Deterministic floor pick (offline / 402 / parse-fail fallback, §15.1).
    case floorFallback
    /// Cold-start SIMPLE mode (<30 days history, §14.2).
    case simple
}

// MARK: - Skip reason (on WorkoutPlan via skipReasonRaw, §8/§15.2)

enum SkipReason: String, Codable, Sendable {
    /// Floor forced recovery — body said no. Must NOT count against adherence.
    case floorForced
    /// User chose not to do it — counts toward adherence/skip propensity.
    case userSkipped
    /// No venue available and no fallback taken (§15.4).
    case venueUnavailable
}
