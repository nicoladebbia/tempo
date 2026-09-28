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

// MARK: - SupplementDecision

/// A single day's take/skip decision for one supplement, produced by the
/// meal-plan AI and stored on `WeeklyMealPlan.supplementDecisions`. Surfaced as
/// "Today's supplements" so the user sees take/skip + why. Codable (not a
/// SwiftData model) — it lives inside the plan's JSON blob, keyed by weekday.
struct SupplementDecision: Codable, Hashable, Identifiable {
    /// Matches a `Supplement.name` on the user's shelf.
    var name: String
    var take: Bool
    /// WHEN to take it, in plain words — "with breakfast", "after lunch",
    /// "post-training", "before bed". Nil/empty for a skip. This is the
    /// nutritionist telling the user not just whether but when.
    var timing: String?
    var reason: String?

    var id: String {
        name
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

    // MARK: - Product (all optional — added Sep 2026, lightweight migration)

    /// Brand as printed on the label, e.g. "Thorne", "Optimum Nutrition".
    var brand: String?

    /// Barcode the product was scanned from (UPC/EAN), if any.
    var upc: String?

    /// Servings in a full, new container — what a restock resets
    /// `servingsRemaining` to, and the base for the reorder warning.
    var servingsPerContainer: Double?

    /// When `servingsRemaining` was last reset by a restock.
    var lastRestockedAt: Date?

    /// When the "you're running low" reorder alert last fired. Compared
    /// against `lastRestockedAt` (`SupplementReorderService.shouldSendReorderAlert`)
    /// so the alert fires at most once per restock cycle — a restock that's
    /// more recent than the last alert starts a fresh cycle without needing to
    /// clear this field. nil = never alerted. Additive, lightweight migration.
    var lastReorderAlertAt: Date?

    // MARK: - Timing (all optional)

    /// User override of WHEN to take it (`SupplementTimingAnchor.rawValue`).
    /// nil → the app decides (plan AI timing, else the kind's default).
    var timingAnchorRaw: String?

    /// User-pinned clock time (minutes after midnight). Wins over any anchor.
    var pinnedMinutes: Int?

    /// Per-supplement reminder switch. nil → on.
    var remindersEnabled: Bool?

    // MARK: - Computed

    @Transient
    var kind: SupplementKind {
        get { SupplementKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    @Transient
    var timingAnchorOverride: SupplementTimingAnchor? {
        get { timingAnchorRaw.flatMap(SupplementTimingAnchor.init(rawValue:)) }
        set { timingAnchorRaw = newValue?.rawValue }
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
