import Foundation

// MARK: - Inputs

/// One logged day. `nutrients` are DAY TOTALS in each nutrient's own unit
/// (food + supplements already summed by the caller).
struct DailyIntake: Sendable, Equatable {
    let date: String // yyyy-MM-dd
    let kcal: Double
    let proteinGrams: Double
    let nutrients: [Nutrient: Double]
}

/// Life context that explains WHY a gap exists. Every field is optional:
/// the detector never invents a signal it wasn't given.
struct NutritionContext: Sendable, Equatable {
    /// Mean minutes outdoors in daylight per day (HealthKit `timeInDaylight`) over the window.
    var avgDaylightMinutes: Double?
    /// Latitude in degrees (north positive); with `month` it flags low winter sun.
    var latitude: Double?
    var month: Int?
    var avgSleepHours: Double?
    var hardTrainingDaysPerWeek: Int?
}

// MARK: - Output

struct NutritionGap: Sendable, Equatable, Codable {
    enum Subject: Sendable, Equatable, Codable, Hashable {
        case protein
        case nutrient(Nutrient)

        var displayName: String {
            switch self {
            case .protein: "Protein"
            case let .nutrient(n): n.displayName
            }
        }
    }

    enum Severity: Int, Sendable, Codable, Comparable {
        case mild = 1, moderate = 2, high = 3
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    let subject: Subject
    let averageIntake: Double
    let target: Double
    let unit: String
    /// averageIntake / target (0.6 = 60% of target).
    let percentOfTarget: Double
    let shortfallPerDay: Double
    let severity: Severity
    /// Plain-language causes drawn from context, e.g. "little daylight lately".
    let reasons: [String]
}

struct NutritionOverage: Sendable, Equatable, Codable {
    let nutrient: Nutrient
    let averageIntake: Double
    let limit: Double
    let isUpperLimit: Bool // true = tolerable upper level, false = soft limit (sodium)
}

struct GapAnalysis: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case ok
        /// Fewer than `GapDetector.minimumCompleteDays` well-logged days. The app must say
        /// "log a few more days" and show no gaps: missing logs are not deficiencies.
        case insufficientData(completeDays: Int)
        case unsupportedProfile
    }

    let status: Status
    let completeDays: Int
    let gaps: [NutritionGap] // most important first
    let overages: [NutritionOverage]
}

// MARK: - Detector

/// Finds what the user is actually low on, from logged intake. Pure and
/// deterministic: same inputs, same answer, no AI, no network.
struct GapDetector: Sendable {
    /// A day counts only if at least this share of the calorie target was logged.
    /// Otherwise a half-logged day reads as a deficiency in everything.
    static let minimumLogCoverage = 0.6
    static let minimumCompleteDays = 3

    /// Below this many minutes a day outdoors, we treat sun exposure as low.
    /// Editorial heuristic (not a medical threshold) used only to explain and
    /// escalate vitamin D gaps, never to diagnose.
    static let lowDaylightMinutes = 20.0

    /// Editorial priority so that, at equal severity, the nutrients people most
    /// commonly miss and that matter for an active person rank first.
    private static let highPriority: Set<NutritionGap.Subject> = [
        .protein, .nutrient(.vitaminD), .nutrient(.magnesium), .nutrient(.potassium), .nutrient(.iron),
        .nutrient(.calcium), .nutrient(.zinc), .nutrient(.vitaminB12), .nutrient(.fiber), .nutrient(.epa), .nutrient(.dha),
    ]

    func analyze(
        profile: NutritionProfile,
        days: [DailyIntake],
        calorieTarget: Double,
        proteinTargetGrams: Double,
        context: NutritionContext = NutritionContext()
    ) -> GapAnalysis {
        guard let targets = NutrientTargets.targets(for: profile) else {
            return GapAnalysis(status: .unsupportedProfile, completeDays: 0, gaps: [], overages: [])
        }

        let complete = days.filter { calorieTarget <= 0 || $0.kcal >= calorieTarget * Self.minimumLogCoverage }
        guard complete.count >= Self.minimumCompleteDays else {
            return GapAnalysis(status: .insufficientData(completeDays: complete.count), completeDays: complete.count, gaps: [], overages: [])
        }
        let n = Double(complete.count)

        var gaps: [NutritionGap] = []
        var overages: [NutritionOverage] = []

        if proteinTargetGrams > 0 {
            let avg = complete.map(\.proteinGrams).reduce(0, +) / n
            if let gap = makeGap(.protein, avg: avg, target: proteinTargetGrams, unit: "g", reasons: proteinReasons(context)) {
                gaps.append(gap)
            }
        }

        for target in targets {
            let avg = complete.map { $0.nutrients[target.nutrient] ?? 0 }.reduce(0, +) / n

            if target.kind == .limit {
                if avg > target.amount {
                    overages.append(NutritionOverage(nutrient: target.nutrient, averageIntake: avg, limit: target.amount, isUpperLimit: false))
                }
                continue
            }
            if let ul = target.upperLimit, target.ulScope == .total, avg > ul {
                overages.append(NutritionOverage(nutrient: target.nutrient, averageIntake: avg, limit: ul, isUpperLimit: true))
            }
            if let gap = makeGap(.nutrient(target.nutrient), avg: avg, target: target.amount, unit: target.nutrient.unit.rawValue,
                                 reasons: reasons(for: target.nutrient, context: context))
            {
                gaps.append(gap)
            }
        }

        // Low sun escalates vitamin D one level: food alone rarely covers it.
        gaps = gaps.map { gap in
            guard gap.subject == .nutrient(.vitaminD), Self.isLowSun(context), gap.severity < .high else { return gap }
            return NutritionGap(subject: gap.subject, averageIntake: gap.averageIntake, target: gap.target, unit: gap.unit,
                                percentOfTarget: gap.percentOfTarget, shortfallPerDay: gap.shortfallPerDay,
                                severity: NutritionGap.Severity(rawValue: gap.severity.rawValue + 1) ?? .high, reasons: gap.reasons)
        }

        gaps.sort { a, b in
            if a.severity != b.severity { return a.severity > b.severity }
            let wa = Self.highPriority.contains(a.subject) ? 1.0 : 0.6
            let wb = Self.highPriority.contains(b.subject) ? 1.0 : 0.6
            let sa = (1 - a.percentOfTarget) * wa
            let sb = (1 - b.percentOfTarget) * wb
            if sa != sb { return sa > sb }
            return a.subject.displayName < b.subject.displayName
        }

        return GapAnalysis(status: .ok, completeDays: complete.count, gaps: gaps, overages: overages)
    }

    // MARK: Helpers

    private func makeGap(_ subject: NutritionGap.Subject, avg: Double, target: Double, unit: String, reasons: [String]) -> NutritionGap? {
        guard target > 0 else { return nil }
        let pct = avg / target
        let severity: NutritionGap.Severity
        switch pct {
        case ..<0.5: severity = .high
        case ..<0.75: severity = .moderate
        case ..<0.9: severity = .mild
        default: return nil
        }
        return NutritionGap(subject: subject, averageIntake: avg, target: target, unit: unit, percentOfTarget: pct,
                            shortfallPerDay: target - avg, severity: severity, reasons: reasons)
    }

    static func isLowSun(_ context: NutritionContext) -> Bool {
        if let minutes = context.avgDaylightMinutes, minutes < lowDaylightMinutes { return true }
        if let lat = context.latitude, let month = context.month, abs(lat) >= 35 {
            // Winter at the user's hemisphere: Nov-Mar north, May-Sep south.
            let winterNorth = [11, 12, 1, 2, 3].contains(month)
            let winterSouth = [5, 6, 7, 8, 9].contains(month)
            return lat > 0 ? winterNorth : winterSouth
        }
        return false
    }

    private func reasons(for nutrient: Nutrient, context: NutritionContext) -> [String] {
        var out: [String] = []
        switch nutrient {
        case .vitaminD:
            if let minutes = context.avgDaylightMinutes, minutes < Self.lowDaylightMinutes {
                out.append("You averaged only \(Int(minutes.rounded())) min of daylight a day.")
            } else if Self.isLowSun(context) {
                out.append("Winter sun at your latitude is too weak to make much vitamin D.")
            }
        case .magnesium:
            if let sleep = context.avgSleepHours, sleep < 7 {
                out.append("Short sleep (\(String(format: "%.1f", sleep)) h) makes magnesium matter more.")
            }
            if let hard = context.hardTrainingDaysPerWeek, hard >= 4 {
                out.append("Heavy training weeks (\(hard) hard days) use more magnesium.")
            }
        case .iron:
            if let hard = context.hardTrainingDaysPerWeek, hard >= 4 {
                out.append("Frequent hard training raises iron losses.")
            }
        default:
            break
        }
        return out
    }

    private func proteinReasons(_ context: NutritionContext) -> [String] {
        if let hard = context.hardTrainingDaysPerWeek, hard >= 3 {
            return ["You train hard \(hard) days a week, so protein is what repairs it."]
        }
        return []
    }
}
