import Foundation

// MARK: - SupplementCatalogSlug

//
// The user's shelf logs a coarse `SupplementKind` (protein/vitamin/other/…)
// plus a free-text `name`. The curated catalog is keyed one level finer (a
// specific product category — "whey_protein", "vitamin_d3", "caffeine"),
// so `match` disambiguates (kind, name) down to a slug. Returning nil means
// "no curated entry" — the picks endpoint falls back to the AI suggestion
// path rather than force-matching something wrong (e.g. an "egg protein"
// shelf item must NOT get whey-protein picks).
//
// This mapping intentionally covers exactly the 20 types researched for
// SupplementCuratedCatalog — adding a curated category means adding both a
// case here AND an entry there.

enum SupplementCatalogSlug: String, CaseIterable, Sendable {
    case creatineMonohydrate = "creatine_monohydrate"
    case wheyProtein = "whey_protein"
    case plantProtein = "plant_protein"
    case caseinProtein = "casein_protein"
    case vitaminD3 = "vitamin_d3"
    case omega3FishOil = "omega3_fish_oil"
    case magnesium
    case multivitamin
    case zinc
    case vitaminC = "vitamin_c"
    case b12
    case iron
    case electrolytes
    case preworkout
    case caffeine
    case melatonin
    case collagen
    case ashwagandha
    case betaAlanine = "beta_alanine"
    case citrulline
    case probiotic

    /// `kind` is the iOS `SupplementKind.rawValue` from the route path
    /// (already validated by the controller). `name` is the shelf item's
    /// free-text name, e.g. "Whey Isolate", "Vitamin D3 + K2", lowercased
    /// here for matching.
    static func match(kind: String, name: String) -> SupplementCatalogSlug? {
        let n = name.lowercased()

        switch kind {
        case "creatine":
            // Creatine monohydrate is the one form with an overwhelming
            // evidence/cost/purity case — no need to branch on name.
            return .creatineMonohydrate

        case "omega3":
            return .omega3FishOil

        case "multivitamin":
            return .multivitamin

        case "electrolytes":
            return .electrolytes

        case "preworkout":
            return .preworkout

        case "protein":
            if n.contains("casein") {
                return .caseinProtein
            }
            if containsAny(n, ["plant", "vegan", "pea protein", "rice protein", "soy protein"]) {
                return .plantProtein
            }
            if n.contains("whey") || n.isEmpty {
                return .wheyProtein
            }
            // e.g. "egg protein", "collagen protein" logged under kind
            // .protein — not in the curated list, let the AI fallback handle it.
            return nil

        case "vitamin":
            if containsAny(n, ["d3", "vitamin d", "d + k2", "d+k2"]) {
                return .vitaminD3
            }
            if n.contains("magnesium") {
                return .magnesium
            }
            if n.contains("zinc") {
                return .zinc
            }
            if n.contains("vitamin c") || n.contains("ascorbic") {
                return .vitaminC
            }
            if n.contains("b12") || n.contains("cobalamin") {
                return .b12
            }
            if n.contains("iron") || n.contains("ferrous") {
                return .iron
            }
            return nil

        case "other":
            if n.contains("caffeine") {
                return .caffeine
            }
            if n.contains("melatonin") {
                return .melatonin
            }
            if n.contains("collagen") {
                return .collagen
            }
            if n.contains("ashwagandha") {
                return .ashwagandha
            }
            if containsAny(n, ["beta-alanine", "beta alanine", "betaalanine"]) {
                return .betaAlanine
            }
            if n.contains("citrulline") {
                return .citrulline
            }
            if n.contains("probiotic") {
                return .probiotic
            }
            return nil

        default:
            return nil
        }
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
