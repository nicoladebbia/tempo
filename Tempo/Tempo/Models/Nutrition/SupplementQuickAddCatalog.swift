//
// SupplementQuickAddCatalog.swift
// Tempo
//
// Static "tap the ones you own" catalog for the Quick Add grid on the
// supplement shelf. Adding supplements one at a time is tedious, so this
// gives the ~22 most common ones a pre-filled kind/dose/protein/daily-default
// so the user just taps and confirms brand + servings (both skippable).
// Pure data — no SwiftData, no networking — so it's trivially testable and
// safe to read from any thread.
//

import Foundation

// MARK: - SupplementQuickAddItem

struct SupplementQuickAddItem: Identifiable, Hashable, Sendable {
    /// The catalog name doubles as the id and the shelf `Supplement.name` —
    /// duplicate detection against the existing shelf matches on this,
    /// case-insensitively.
    var id: String {
        name
    }

    let name: String
    let kind: SupplementKind
    /// Typical labeled dose for one serving, e.g. "5 g", "1 scoop (30 g)".
    let dose: String
    /// Protein grams per serving — non-zero only for protein powders, so a
    /// tapped scoop counts toward the day's protein target immediately.
    let proteinGrams: Double
    /// Calories / carbs / fat per serving (0 = none). A ticked dose adds
    /// these, with the protein, to today's totals.
    var calories: Double = 0
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    /// Seeded `takeDaily` — evidence-based per item (not just per kind), so
    /// e.g. Vitamin D3 defaults daily even though `.vitamin` itself doesn't.
    let takeDaily: Bool
    /// SF Symbol for the quick-add chip and, until edited, the shelf row.
    let icon: String

    /// "120 kcal · 24g P" — nil for supplements that carry no macros.
    var macroSummary: String? {
        guard calories > 0 || proteinGrams > 0 else { return nil }
        var parts: [String] = []
        if calories > 0 { parts.append("\(Int(calories.rounded())) kcal") }
        if proteinGrams > 0 { parts.append("\(Int(proteinGrams.rounded()))g P") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - SupplementQuickAddCatalog

enum SupplementQuickAddCatalog {
    /// ~22 most-added supplements, in the order they should appear in the grid.
    static let items: [SupplementQuickAddItem] = [
        SupplementQuickAddItem(
            name: "Creatine Monohydrate",
            kind: .creatine,
            dose: "5 g",
            proteinGrams: 0,
            takeDaily: true,
            icon: "bolt.fill"
        ),
        SupplementQuickAddItem(
            name: "Whey Protein",
            kind: .protein,
            dose: "1 scoop (30 g)",
            proteinGrams: 24,
            calories: 120,
            carbsGrams: 3,
            fatGrams: 1.5,
            takeDaily: false,
            icon: "dumbbell.fill"
        ),
        SupplementQuickAddItem(
            name: "Mass Gainer",
            kind: .protein,
            dose: "1 serving (150 g)",
            proteinGrams: 50,
            calories: 620,
            carbsGrams: 95,
            fatGrams: 6,
            takeDaily: false,
            icon: "scalemass.fill"
        ),
        SupplementQuickAddItem(
            name: "Plant Protein",
            kind: .protein,
            dose: "1 scoop (33 g)",
            proteinGrams: 21,
            calories: 120,
            carbsGrams: 4,
            fatGrams: 2.5,
            takeDaily: false,
            icon: "leaf.fill"
        ),
        SupplementQuickAddItem(
            name: "Casein",
            kind: .protein,
            dose: "1 scoop (33 g)",
            proteinGrams: 24,
            calories: 120,
            carbsGrams: 4,
            fatGrams: 1,
            takeDaily: false,
            icon: "moon.stars.fill"
        ),
        SupplementQuickAddItem(name: "Vitamin D3", kind: .vitamin, dose: "2000 IU", proteinGrams: 0, takeDaily: true, icon: "sun.max.fill"),
        SupplementQuickAddItem(
            name: "D3 + K2",
            kind: .vitamin,
            dose: "5000 IU / 100 mcg",
            proteinGrams: 0,
            takeDaily: true,
            icon: "sun.horizon.fill"
        ),
        SupplementQuickAddItem(name: "Omega-3 Fish Oil", kind: .omega3, dose: "1000 mg", proteinGrams: 0, takeDaily: false, icon: "fish"),
        SupplementQuickAddItem(
            name: "Magnesium Glycinate",
            kind: .vitamin,
            dose: "200 mg",
            proteinGrams: 0,
            takeDaily: true,
            icon: "moon.zzz.fill"
        ),
        SupplementQuickAddItem(name: "Zinc", kind: .vitamin, dose: "15 mg", proteinGrams: 0, takeDaily: true, icon: "shield.fill"),
        SupplementQuickAddItem(
            name: "Multivitamin",
            kind: .multivitamin,
            dose: "1 tablet",
            proteinGrams: 0,
            takeDaily: true,
            icon: "pills.fill"
        ),
        SupplementQuickAddItem(
            name: "Vitamin C",
            kind: .vitamin,
            dose: "500 mg",
            proteinGrams: 0,
            takeDaily: true,
            icon: "cross.case.fill"
        ),
        SupplementQuickAddItem(name: "B12", kind: .vitamin, dose: "1000 mcg", proteinGrams: 0, takeDaily: true, icon: "bolt.heart.fill"),
        SupplementQuickAddItem(name: "Iron", kind: .vitamin, dose: "18 mg", proteinGrams: 0, takeDaily: true, icon: "cross.vial.fill"),
        SupplementQuickAddItem(
            name: "Electrolytes",
            kind: .electrolytes,
            dose: "1 packet",
            proteinGrams: 0,
            takeDaily: false,
            icon: "drop.fill"
        ),
        SupplementQuickAddItem(
            name: "Pre-Workout",
            kind: .preworkout,
            dose: "1 scoop",
            proteinGrams: 0,
            takeDaily: false,
            icon: "flame.fill"
        ),
        SupplementQuickAddItem(
            name: "Caffeine",
            kind: .preworkout,
            dose: "200 mg",
            proteinGrams: 0,
            takeDaily: false,
            icon: "cup.and.saucer.fill"
        ),
        SupplementQuickAddItem(
            name: "Ashwagandha",
            kind: .other,
            dose: "600 mg",
            proteinGrams: 0,
            takeDaily: true,
            icon: "leaf.arrow.circlepath"
        ),
        SupplementQuickAddItem(name: "Melatonin", kind: .other, dose: "3 mg", proteinGrams: 0, takeDaily: false, icon: "powersleep"),
        SupplementQuickAddItem(
            name: "Collagen",
            kind: .other,
            dose: "1 scoop (10 g)",
            proteinGrams: 9,
            calories: 35,
            takeDaily: true,
            icon: "sparkles"
        ),
        SupplementQuickAddItem(
            name: "Probiotic",
            kind: .other,
            dose: "1 capsule",
            proteinGrams: 0,
            takeDaily: true,
            icon: "leaf.circle.fill"
        ),
        SupplementQuickAddItem(
            name: "Beta-Alanine",
            kind: .preworkout,
            dose: "3.2 g",
            proteinGrams: 0,
            takeDaily: false,
            icon: "bolt.circle.fill"
        ),
        SupplementQuickAddItem(
            name: "Citrulline",
            kind: .preworkout,
            dose: "6 g",
            proteinGrams: 0,
            takeDaily: false,
            icon: "heart.circle.fill"
        ),
    ]

    /// The grid should skip anything already on the shelf — matched by name,
    /// case-insensitively (a user's "whey protein" shouldn't duplicate the
    /// catalog's "Whey Protein").
    static func available(excluding shelfNames: [String]) -> [SupplementQuickAddItem] {
        let lowered = Set(shelfNames.map { $0.lowercased() })
        return items.filter { !lowered.contains($0.name.lowercased()) }
    }
}
