//
// FoodScore.swift
// Tempo
//
// Tempo's 0–100 product score, modelled on Yuka's published method:
//   60 pts nutrition quality — from the Nutri-Score points (official when the
//          source has them, else estimated here with the 2023 algorithm)
//   30 pts additives — EFSA overexposure risk per additive (Open Food Facts
//          additives taxonomy, bundled as FoodAdditives.json) plus a few
//          regulatory overrides below; any HIGH-risk additive caps the total
//          at 49 ("poor"), as Yuka does
//   10 pts organic label
// 75+ excellent · 50–74 good · 25–49 poor · <25 bad.
//
// Pure and deterministic — unit-tested in FoodScoreTests.
//

import Foundation

// MARK: - FoodScore

struct FoodScore: Equatable, Sendable {
    enum Rating: String, Sendable {
        case excellent
        case good
        case poor
        case bad

        init(score: Int) {
            switch score {
            case 75...: self = .excellent
            case 50 ..< 75: self = .good
            case 25 ..< 50: self = .poor
            default: self = .bad
            }
        }

        var label: String {
            switch self {
            case .excellent: "Excellent"
            case .good: "Good"
            case .poor: "Poor"
            case .bad: "Bad"
            }
        }
    }

    let total: Int
    let rating: Rating
    /// 0–60, 0–30, 0–10.
    let nutritionPoints: Int
    let additivePoints: Int
    let organicPoints: Int
    /// Nutri-Score used for the nutrition part and whether Tempo estimated it.
    let nutriScoreGrade: String
    let nutriScoreEstimated: Bool
    let additives: [FoodAdditive]
    /// A high-risk additive capped the total at 49.
    let cappedByAdditive: Bool

    /// nil when there isn't enough nutrition data to judge the product.
    static func evaluate(_ product: FoodProduct, additiveTable: FoodAdditiveTable = .shared) -> FoodScore? {
        // A score computed from numbers that contradict themselves is a
        // confident wrong answer — show "not scored" instead.
        guard product.implausibilityReason == nil else {
            return nil
        }
        let official = product.nutriScorePoints.flatMap { points in
            product.nutriScoreGrade.map { (points: points, grade: $0.lowercased()) }
        }
        let nutri: (points: Int, grade: String, estimated: Bool)
        if let official, NutriScore.grades.contains(official.grade) {
            nutri = (official.points, official.grade, false)
        } else if let estimate = NutriScore.estimate(product.per100g, isBeverage: product.isBeverage) {
            nutri = (estimate.points, estimate.grade, true)
        } else {
            return nil
        }

        let nutritionPoints = nutritionPart(nutriPoints: nutri.points, grade: nutri.grade, isBeverage: product.isBeverage)
        let additives = Self.distinctAdditiveCodes(product.additives).map { additiveTable.additive(for: $0) }
        let moderate = additives.filter { $0.risk == .moderate }.count
        let hasHigh = additives.contains { $0.risk == .high }
        let additivePoints = hasHigh ? 0 : max(0, 30 - moderate * 10)
        let organicPoints = product.isOrganic ? 10 : 0

        var total = nutritionPoints + additivePoints + organicPoints
        if hasHigh {
            total = min(total, 49)
        }
        return FoodScore(
            total: total,
            rating: Rating(score: total),
            nutritionPoints: nutritionPoints,
            additivePoints: additivePoints,
            organicPoints: organicPoints,
            nutriScoreGrade: nutri.grade,
            nutriScoreEstimated: nutri.estimated,
            additives: additives.sorted { $0.risk.sortOrder < $1.risk.sortOrder },
            cappedByAdditive: hasHigh
        )
    }

    /// OFF lists a family and its variant ("e322" + "e322i"): keep the variant
    /// only, so one ingredient isn't shown — or penalised — twice.
    static func distinctAdditiveCodes(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        let codes = raw.map(FoodAdditiveTable.normalize).filter { seen.insert($0).inserted }
        let parentsOfVariants = Set(codes.compactMap { code in
            let parent = FoodAdditiveTable.parentCode(code)
            return parent == code ? nil : parent
        })
        return codes.filter { !parentsOfVariants.contains($0) }
    }

    /// Nutri-Score points → 0–60, piecewise-linear inside each grade band so
    /// A lands 45–60, B 40–44, C 25–39, D 10–24, E 0–9.
    static func nutritionPart(nutriPoints: Int, grade: String, isBeverage: Bool) -> Int {
        // (grade, points range covered, output range)
        let bands: [(String, ClosedRange<Double>, ClosedRange<Double>)] = isBeverage
            ? [
                ("a", -15 ... 0, 45 ... 60),
                ("b", 1 ... 2, 40 ... 44),
                ("c", 3 ... 6, 25 ... 39),
                ("d", 7 ... 9, 10 ... 24),
                ("e", 10 ... 30, 0 ... 9),
            ]
            : [
                ("a", -15 ... 0, 45 ... 60),
                ("b", 1 ... 2, 40 ... 44),
                ("c", 3 ... 10, 25 ... 39),
                ("d", 11 ... 18, 10 ... 24),
                ("e", 19 ... 40, 0 ... 9),
            ]
        guard let band = bands.first(where: { $0.0 == grade }) else {
            return 0
        }
        let points = min(max(Double(nutriPoints), band.1.lowerBound), band.1.upperBound)
        let span = band.1.upperBound - band.1.lowerBound
        // Fewer Nutri-Score points = healthier = higher output.
        let fraction = span == 0 ? 1 : (band.1.upperBound - points) / span
        return Int((band.2.lowerBound + fraction * (band.2.upperBound - band.2.lowerBound)).rounded())
    }
}

// MARK: - NutriScore

/// Nutri-Score 2023 (general foods) and 2023 beverages, estimated from the
/// per-100 g values we have. Fruit/vegetable/legume content is rarely known,
/// so it scores 0 — the estimate can be slightly harsher than the official
/// grade, which is always preferred when the source provides it.
enum NutriScore {
    static let grades = ["a", "b", "c", "d", "e"]

    static func estimate(_ n: FoodProduct.Nutrients, isBeverage: Bool) -> (points: Int, grade: String)? {
        // Sugars, saturated fat and salt are often missing on small labels —
        // and always missing for Tempo's built-in table, which has no sodium
        // data at all: fall back to 0 sugars/salt when carbs are known (the
        // signal that this is real nutrition data, not a stub), and 40% of
        // fat as saturated.
        guard let kcal = n.kcal,
              let sugars = n.sugars ?? (n.carbs == nil ? nil : 0),
              let satFat = n.saturatedFat ?? n.fat.map({ $0 * 0.4 }),
              let salt = n.salt ?? (n.carbs == nil ? nil : 0)
        else {
            return nil
        }
        let energyKJ = kcal * 4.184
        let protein = n.protein ?? 0
        let fiber = n.fiber ?? 0

        if isBeverage {
            let energy = points(energyKJ, [30, 90, 150, 210, 240, 270, 300, 330, 360, 390])
            let sugar = points(sugars, [0.5, 2, 3.5, 5, 6, 7, 8, 9, 10, 11])
            let negative = energy + sugar + points(satFat, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
                + points(salt, [0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.2, 3.4, 3.6, 3.8, 4.0])
            let positive = points(protein, [1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0]) + points(fiber, [3.0, 4.1, 5.2, 6.3, 7.4])
            let total = negative - positive
            let grade = switch total {
            case ...2: "b"
            case 3 ... 6: "c"
            case 7 ... 9: "d"
            default: "e"
            }
            return (total, grade)
        }

        let negative = points(energyKJ, [335, 670, 1005, 1340, 1675, 2010, 2345, 2680, 3015, 3350])
            + points(sugars, [3.4, 6.8, 10, 14, 17, 20, 24, 27, 31, 34, 37, 41, 44, 48, 51])
            + points(satFat, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
            + points(salt, [0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.2, 3.4, 3.6, 3.8, 4.0])
        let proteinPoints = points(protein, [2.4, 4.8, 7.2, 9.6, 12, 14, 17])
        let fiberPoints = points(fiber, [3.0, 4.1, 5.2, 6.3, 7.4])
        // Protein only counts while the negatives are below 11.
        let positive = fiberPoints + (negative < 11 ? proteinPoints : 0)
        let total = negative - positive
        let grade = switch total {
        case ...0: "a"
        case 1 ... 2: "b"
        case 3 ... 10: "c"
        case 11 ... 18: "d"
        default: "e"
        }
        return (total, grade)
    }

    /// Number of thresholds strictly exceeded.
    private static func points(_ value: Double, _ thresholds: [Double]) -> Int {
        thresholds.count { value > $0 }
    }
}

// MARK: - FoodAdditive

struct FoodAdditive: Equatable, Hashable, Sendable, Identifiable {
    enum Risk: String, Sendable {
        case high
        case moderate
        case low
        /// Not evaluated for overexposure — no known risk.
        case unknown

        var sortOrder: Int {
            switch self {
            case .high: 0
            case .moderate: 1
            case .low: 2
            case .unknown: 3
            }
        }

        var label: String {
            switch self {
            case .high: "High risk"
            case .moderate: "Moderate risk"
            case .low: "Low risk"
            case .unknown: "No known risk"
            }
        }
    }

    /// "e330"
    let code: String
    let name: String
    let risk: Risk
    /// Why an override applies, shown under the additive.
    let note: String?

    var id: String {
        code
    }

    /// "E330"
    var displayCode: String {
        code.uppercased()
    }
}

// MARK: - FoodAdditiveTable

/// The bundled Open Food Facts additives table (name + EFSA overexposure
/// risk), plus regulatory overrides where EFSA's overexposure data is silent.
final class FoodAdditiveTable: Sendable {
    static let shared = FoodAdditiveTable(bundle: .main)

    private let entries: [String: Entry]

    struct Entry: Decodable, Sendable {
        let n: String
        let r: String?
    }

    /// Overrides with a public source. EFSA's overexposure field covers only
    /// ~65 additives; these fill well-known gaps.
    static let overrides: [String: (FoodAdditive.Risk, String)] = [
        "e171": (.high, "Banned in the EU since 2022 (EFSA could not rule out genotoxicity)."),
        "e249": (.high, "Nitrite — same concern as E250."),
        "e102": (.moderate, "EU requires the warning “may have an adverse effect on activity and attention in children”."),
        "e104": (.moderate, "EU requires the warning “may have an adverse effect on activity and attention in children”."),
        "e110": (.moderate, "EU requires the warning “may have an adverse effect on activity and attention in children”."),
        "e122": (.moderate, "EU requires the warning “may have an adverse effect on activity and attention in children”."),
        "e124": (.moderate, "EU requires the warning “may have an adverse effect on activity and attention in children”."),
        "e129": (.moderate, "EU requires the warning “may have an adverse effect on activity and attention in children”."),
        "e320": (.moderate, "Classified by IARC as possibly carcinogenic (group 2B)."),
        "e951": (.moderate, "Classified by IARC as possibly carcinogenic (group 2B, 2023)."),

        // Colours — EU restrictions or banned status beyond the JSON table's own data.
        "e127": (.moderate, "Thyroid-function concerns at high intake; several countries restrict it in children's foods."),
        "e128": (.high, "Banned in the EU since 2007 — its aniline metabolite is a suspected carcinogen."),
        "e153": (.low, "Some sourcing carries a PAH-contamination risk; several countries restrict it."),
        "e173": (.moderate, "EFSA lowered the safe aluminium intake in 2008 — frequent exposure adds up."),

        // Preservatives — same families as the sorbates/benzoates/sulphites/nitrites already rated.
        "e201": (.high, "Same sorbate family as E200/E202."),
        "e203": (.high, "Same sorbate family as E200/E202."),
        "e230": (.moderate, "Fungicide residue on citrus peel; restricted EU use."),
        "e231": (.moderate, "Fungicide residue on citrus peel; restricted EU use."),
        "e232": (.moderate, "Fungicide residue on citrus peel; restricted EU use."),
        "e233": (.moderate, "Fungicide residue on citrus peel; restricted EU use."),
        "e239": (.moderate, "A formaldehyde-releasing preservative, restricted to specific hard cheeses."),
        "e280": (.moderate, "Propionates have been linked to migraine and hyperactivity in some studies."),
        "e281": (.moderate, "Propionates have been linked to migraine and hyperactivity in some studies."),
        "e282": (.moderate, "Propionates have been linked to migraine and hyperactivity in some studies."),
        "e283": (.moderate, "Propionates have been linked to migraine and hyperactivity in some studies."),

        // Antioxidants.
        "e310": (.moderate, "Gallates: EFSA's 2014 re-evaluation flagged possible endocrine effects."),
        "e311": (.moderate, "Gallates: EFSA's 2014 re-evaluation flagged possible endocrine effects."),
        "e312": (.moderate, "Gallates: EFSA's 2014 re-evaluation flagged possible endocrine effects."),
        "e319": (.moderate, "TBHQ — not authorised as a food additive in several countries outside the EU."),
        "e321": (.moderate, "BHT — like BHA, classified by IARC as possibly carcinogenic (group 2B)."),

        // Emulsifiers under active research (gut-microbiome studies, 2022–23).
        "e466": (.moderate, "Carboxymethylcellulose — 2022–23 research links it to gut inflammation."),
        "e468": (.moderate, "Carboxymethylcellulose derivative — same emerging research as E466."),
        "e469": (.moderate, "Carboxymethylcellulose derivative — same emerging research as E466."),

        // Flavour enhancers — same glutamate family as E621 (MSG).
        "e622": (.high, "Same glutamate family as E621 (MSG)."),
        "e623": (.high, "Same glutamate family as E621 (MSG)."),
        "e624": (.high, "Same glutamate family as E621 (MSG)."),
        "e625": (.high, "Same glutamate family as E621 (MSG)."),

        // Sweeteners.
        "e950": (.moderate, "Acesulfame K — EFSA is re-evaluating it after newer metabolic-effect studies."),
        "e952": (.moderate, "Cyclamate — banned in the US since 1969 over carcinogenicity concerns; the EU permits it with an ADI."),
        "e954": (.moderate, "Saccharin — historically flagged as a possible carcinogen; still capped by a strict ADI."),
        "e955": (.moderate, "Sucralose — 2023 research raised gut-microbiome and genotoxicity questions EFSA is reviewing."),
        "e958": (.moderate, "Glycyrrhizin (licorice extract) — linked to high blood pressure and low potassium at regular intake."),
        "e962": (.moderate, "Contains aspartame — same IARC group-2B concern as E951."),
        "e968": (.moderate, "Erythritol — a 2023 Nature Medicine study linked it to higher cardiovascular clotting risk."),

        // Common additives with an established safety record — rated so they read
        // "Low risk" instead of "not evaluated" (EFSA: ADI not specified / no safety concern).
        "e296": (.low, "Malic acid — naturally occurring fruit acid, ADI not specified by EFSA."),
        "e300": (.low, "Vitamin C — EFSA lists no safety concern at food-use levels."),
        "e322": (.low, "Lecithin — a naturally derived emulsifier with no known overexposure risk."),
        "e330": (.low, "Citric acid — ADI not specified by EFSA; no known overexposure risk."),
        "e331": (.low, "Sodium citrate — same profile as citric acid."),
        "e400": (.low, "Alginic acid — a seaweed-derived thickener with no known overexposure risk."),
        "e401": (.low, "Sodium alginate — same profile as alginic acid."),
        "e406": (.low, "Agar — a seaweed-derived gelling agent, ADI not specified."),
        "e410": (.low, "Locust bean gum — ADI not specified by EFSA."),
        "e412": (.low, "Guar gum — ADI not specified by EFSA."),
        "e414": (.low, "Gum arabic — ADI not specified by EFSA."),
        "e415": (.low, "Xanthan gum — ADI not specified by EFSA."),
        "e440": (.low, "Pectin — a fruit-derived gelling agent, no known overexposure risk."),
        "e460": (.low, "Cellulose — plant fibre, no known overexposure risk."),
        "e500": (.low, "Sodium bicarbonate/carbonate — no known overexposure risk."),
        "e501": (.low, "Potassium carbonate — no known overexposure risk."),
        "e575": (.low, "Glucono-delta-lactone — a naturally derived acidifier, no known overexposure risk."),
    ]

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource: "FoodAdditives", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else {
            entries = [:]
            return
        }
        entries = decoded
    }

    init(entries: [String: Entry]) {
        self.entries = entries
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    func additive(for rawCode: String) -> FoodAdditive {
        let code = Self.normalize(rawCode)
        // "e322i" → fall back to the parent "e322".
        let entry = entries[code] ?? entries[Self.parentCode(code)]
        let name = entry?.n ?? code.uppercased()
        if let override = Self.overrides[code] {
            return FoodAdditive(code: code, name: name, risk: override.0, note: override.1)
        }
        let risk: FoodAdditive.Risk = switch entry?.r {
        case "high": .high
        case "moderate": .moderate
        case "no",
             "low": .low
        default: .unknown
        }
        return FoodAdditive(code: code, name: name, risk: risk, note: nil)
    }

    /// "e322i" → "e322", "e160aii" → "e160" (sub-variants share the parent's entry).
    static func parentCode(_ code: String) -> String {
        guard code.hasPrefix("e") else {
            return code
        }
        return "e" + code.dropFirst().prefix { $0.isNumber }
    }

    /// "en:E330" / "E 330" → "e330".
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.split(separator: ":").last.map(String.init) ?? raw
        return trimmed.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
    }
}
