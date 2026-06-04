//
// Supplement.swift
// Tempo
//
// The user's owned supplement shelf. The meal-plan AI reads this (like it
// reads the pantry) and decides, per day, which supplements to take or skip —
// e.g. creatine daily, whey only when the day's whole-food meals fall short on
// protein, omega-3 periodized around hard sessions. The app NEVER tells the
// user to buy supplements they don't own; this model is purely "what's on the
// shelf".
//

import Foundation
import SwiftData

// MARK: - SupplementKind

/// Coarse category. Drives the AI's scheduling logic (creatine is daily,
/// protein fills a macro gap, omega-3 is periodized) and the shelf UI icon.
enum SupplementKind: String, Codable, CaseIterable, Sendable {
    case protein
    case creatine
    case omega3
    case multivitamin
    case vitamin // single-vitamin (D, C, zinc, etc.)
    case preworkout
    case electrolytes
    case other

    var displayName: String {
        switch self {
        case .protein: "Protein"
        case .creatine: "Creatine"
        case .omega3: "Omega-3"
        case .multivitamin: "Multivitamin"
        case .vitamin: "Vitamin / Mineral"
        case .preworkout: "Pre-workout"
        case .electrolytes: "Electrolytes"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .protein: "dumbbell"
        case .creatine: "bolt.fill"
        case .omega3: "fish"
        case .multivitamin: "pills.fill"
        case .vitamin: "pill.fill"
        case .preworkout: "flame.fill"
        case .electrolytes: "drop.fill"
        case .other: "capsule"
        }
    }

    /// Supplements whose evidence supports a steady DAILY dose regardless of
    /// training (the AI schedules these every day unless the user disables it).
    /// Creatine is the canonical case. Everything else is conditional —
    /// protein fills a gap, omega-3/recovery is periodized.
    var defaultsToDaily: Bool {
        self == .creatine
    }
}

// MARK: - Supplement

@Model
final class Supplement {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    /// User-facing name, e.g. "Whey Isolate", "Creatine Monohydrate".
    var name: String

    var kindRaw: String

    // MARK: - Dosing

    /// Free-text label of one serving's dose, e.g. "25 g", "5 g", "1000 mg",
    /// "1 capsule". Display-only; the AI reads it for context.
    var dosePerServing: String

    /// Protein grams delivered by one serving — set for protein powders so the
    /// AI can count a scheduled scoop toward the day's protein target. Nil /
    /// zero for non-protein supplements.
    var proteinGramsPerServing: Double

    /// Servings left in the tub/bottle. The AI must not schedule more than this
    /// and should flag "running low". Optional tracking — 0 means unknown/empty.
    var servingsRemaining: Double

    /// When true, the AI schedules this every day by default (creatine). When
    /// false, it's conditional (protein gap / periodized recovery). Seeded from
    /// `SupplementKind.defaultsToDaily` at creation but user-overridable.
    var takeDaily: Bool

    // MARK: - Preferences

    /// Free-text user note the AI should honor, e.g. "only on training days",
    /// "I get bloated with two scoops". Sanitized before entering the prompt.
    var userNotes: String?

    // MARK: - Lifecycle

    var createdAt: Date

    var updatedAt: Date

    /// Soft-delete: archived supplements are kept for history but excluded from
    /// the shelf the AI reads.
    var isArchived: Bool

    // MARK: - Computed

    @Transient
    var kind: SupplementKind {
        get { SupplementKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    @Transient
    var isRunningLow: Bool {
        servingsRemaining > 0 && servingsRemaining <= 5
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        kind: SupplementKind,
        dosePerServing: String = "",
        proteinGramsPerServing: Double = 0,
        servingsRemaining: Double = 0,
        takeDaily: Bool? = nil,
        userNotes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        kindRaw = kind.rawValue
        self.dosePerServing = dosePerServing
        self.proteinGramsPerServing = max(0, proteinGramsPerServing)
        self.servingsRemaining = max(0, servingsRemaining)
        // Seed daily-default from the kind unless the caller overrides.
        self.takeDaily = takeDaily ?? kind.defaultsToDaily
        self.userNotes = userNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
}
