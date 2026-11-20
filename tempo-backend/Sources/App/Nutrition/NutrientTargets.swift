import Foundation

// MARK: - Profile

/// Who the targets are for. v1 covers healthy adults 19+ only. Children,
/// teenagers, pregnancy and lactation have different tables and are NOT
/// guessed: `NutrientTargets.targets(for:)` returns nil for them and the app
/// shows "ask a professional" instead of numbers.
struct NutritionProfile: Sendable, Equatable, Codable {
    enum Sex: String, Sendable, Codable { case male, female }

    var sex: Sex
    var ageYears: Int
    var isPregnantOrLactating: Bool = false
}

// MARK: - Target

struct NutrientTarget: Sendable, Equatable, Codable {
    enum Kind: String, Sendable, Codable {
        /// Recommended Dietary Allowance (meets the needs of ~97.5% of healthy people).
        case rda
        /// Adequate Intake (set when there isn't enough evidence for an RDA).
        case ai
        /// Widely used guidance with no official RDA (e.g. EPA+DHA).
        case guidance
        /// A ceiling to stay under, not a goal (sodium).
        case limit
    }

    /// Where the tolerable upper intake level (UL) applies.
    enum ULScope: String, Sendable, Codable {
        /// UL applies to everything you eat and take (vitamin D, calcium, iron, zinc...).
        case total
        /// UL applies only to supplements/fortification (magnesium, niacin, vitamin E, folic acid).
        /// Food alone doesn't trip it, so the gap detector ignores it; the supplement checker enforces it.
        /// KNOWN LIMIT: vitamin A's UL is for preformed retinol, which liver can exceed from food alone.
        /// We don't track retinol yet, so the detector can't warn about liver-heavy diets (see docs).
        case supplementsOnly
    }

    let nutrient: Nutrient
    let amount: Double // in nutrient.unit per day
    let kind: Kind
    let upperLimit: Double?
    let ulScope: ULScope?
}

// MARK: - Table

/// NIH Office of Dietary Supplements / NASEM Dietary Reference Intakes for
/// adults. Source pages: ods.od.nih.gov/factsheets/<Nutrient>-HealthProfessional
/// (spot-checked 2026-11-20). Update the table, not the logic, when a source
/// changes, and keep `NutrientTargetsTests` in step.
enum NutrientTargets {
    static let minimumAge = 19

    static func targets(for profile: NutritionProfile) -> [NutrientTarget]? {
        guard profile.ageYears >= minimumAge, !profile.isPregnantOrLactating else { return nil }

        let male = profile.sex == .male
        let age = profile.ageYears
        let over50 = age >= 51
        let over70 = age >= 71

        func t(
            _ n: Nutrient, _ amount: Double, _ kind: NutrientTarget.Kind = .rda,
            ul: Double? = nil, scope: NutrientTarget.ULScope? = nil
        ) -> NutrientTarget {
            NutrientTarget(nutrient: n, amount: amount, kind: kind, upperLimit: ul, ulScope: ul == nil ? nil : (scope ?? .total))
        }

        return [
            // Vitamins
            t(.vitaminA, male ? 900 : 700, ul: 3000, scope: .supplementsOnly), // µg RAE, UL = preformed
            t(.vitaminC, male ? 90 : 75, ul: 2000),
            t(.vitaminD, over70 ? 20 : 15, ul: 100), // µg (600/800 IU)
            t(.vitaminE, 15, ul: 1000, scope: .supplementsOnly),
            t(.vitaminK, male ? 120 : 90, .ai),
            t(.thiamin, male ? 1.2 : 1.1),
            t(.riboflavin, male ? 1.3 : 1.1),
            t(.niacin, male ? 16 : 14, ul: 35, scope: .supplementsOnly),
            t(.pantothenicAcid, 5, .ai),
            t(.vitaminB6, over50 ? (male ? 1.7 : 1.5) : 1.3, ul: 100),
            t(.folate, 400, ul: 1000, scope: .supplementsOnly), // µg DFE; UL = folic acid
            t(.vitaminB12, 2.4),
            t(.choline, male ? 550 : 425, .ai, ul: 3500),
            // Minerals
            t(.calcium, (male && !over70) ? 1000 : (!male && !over50) ? 1000 : 1200, ul: over50 ? 2000 : 2500),
            t(.iron, (!male && !over50) ? 18 : 8, ul: 45),
            t(.magnesium, male ? (age <= 30 ? 400 : 420) : (age <= 30 ? 310 : 320), ul: 350, scope: .supplementsOnly),
            t(.phosphorus, 700, ul: over70 ? 3000 : 4000),
            t(.potassium, male ? 3400 : 2600, .ai),
            t(.sodium, 2300, .limit), // NASEM Chronic Disease Risk Reduction level
            t(.zinc, male ? 11 : 8, ul: 40),
            t(.copper, 0.9, ul: 10), // mg (USDA reports copper in mg)
            t(.manganese, male ? 2.3 : 1.8, .ai, ul: 11),
            t(.selenium, 55, ul: 400),
            // Fats and fiber
            t(.omega3ALA, male ? 1.6 : 1.1, .ai),
            t(.epa, 0.125, .guidance), // EPA+DHA ~250 mg/day combined (EFSA); split evenly
            t(.dha, 0.125, .guidance),
            t(.fiber, male ? (over50 ? 30 : 38) : (over50 ? 21 : 25), .ai),
        ]
    }

    static func target(for nutrient: Nutrient, profile: NutritionProfile) -> NutrientTarget? {
        targets(for: profile)?.first { $0.nutrient == nutrient }
    }
}
