//
// ReadinessTrendMath.swift
// Tempo
//
// The trend-derivation intelligence (docs/INTELLIGENT_TRAINING_SYSTEM.md §6.1).
// Pure functions over arrays of daily values — no SwiftData, no DailyRecovery
// dependency (callers extract the arrays). This is what D0 stubbed: D0 fed Haiku
// synthetic z-scores; D1 derives them from real 30-day history.
//
// The method, not just the cutoff, matters (§6.1):
//   • HRV (rMSSD) is log-normal + noisy → work in ln(rMSSD), 7-day acute mean vs
//     30-day baseline mean/SD, deviation as a z-score. A single day's rMSSD swings
//     ±20% on noise; the 7-day mean is the actionable quantity. [L]
//   • RHR is ~normal → raw rolling mean + SD; deviation in absolute bpm (primary)
//     with a z backstop. [D]
//   • NEVER impute a missing day as 0 — a zero fakes an HRV crash → false SEVERE.
//     Compute over VALID samples; gaps just shrink n. [§6.3]
//   • Cold-start gates: ≥14 valid samples for the floor's raw routes; the 7-day
//     acute window needs ≥4 valid of the last 7.
//

import Foundation

enum ReadinessTrendMath {

    // MARK: - Sample-count gates (§6.3, §14.2)

    /// The floor's raw z-score routes need at least this many valid samples.
    static let minBaselineSamples = ReadinessPicture.minBaselineSamples // 14
    /// The 7-day acute window needs at least this many valid of the last 7.
    static let minAcuteSamples = 4

    // MARK: - HRV (ln-rMSSD z-score)

    /// z-score of the trailing-`acuteDays` mean of ln(rMSSD) vs the trailing-
    /// `baselineDays` baseline (mean/SD of ln(rMSSD)). nil when either window
    /// lacks enough valid samples or the baseline SD is ~0.
    ///
    /// - Parameters ordered most-recent-LAST is NOT assumed; pass the trailing
    ///   window already sliced. `recent` = last `acuteDays`; `baseline` = last
    ///   `baselineDays`. Both may contain nil (missing days) — those are dropped.
    static func hrvZScore(
        recentLnInput recent: [Double?],
        baselineInput baseline: [Double?],
        minAcute: Int = minAcuteSamples,
        minBaseline: Int = minBaselineSamples
    ) -> Double? {
        let recentValid = recent.compactMap { $0 }.filter { $0 > 0 }.map(log)
        let baselineValid = baseline.compactMap { $0 }.filter { $0 > 0 }.map(log)

        guard recentValid.count >= minAcute, baselineValid.count >= minBaseline else { return nil }

        let acuteMean = mean(recentValid)
        let baseMean = mean(baselineValid)
        guard let baseSD = standardDeviation(baselineValid), baseSD > 1e-6 else { return nil }

        return (acuteMean - baseMean) / baseSD
    }

    /// 7-day trend direction of a series (most-recent values weigh the verdict).
    /// Uses the sign of the simple slope; nil-tolerant.
    static func trend7d(_ series: [Double?]) -> TrendDirection {
        let valid = series.compactMap { $0 }
        guard valid.count >= 3 else { return .flat }
        let s = slope(valid)
        // Threshold relative to series scale so noise reads as flat.
        let scale = max(abs(mean(valid)), 1e-6)
        let normalized = s / scale
        if normalized > 0.01 { return .rising }
        if normalized < -0.01 { return .falling }
        return .flat
    }

    // MARK: - RHR / Respiratory (raw deviation + z)

    /// Absolute deviation (today − baseline mean) in the series' native unit.
    /// nil when the baseline lacks enough valid samples.
    static func deviation(today: Double?, baselineInput baseline: [Double?], minBaseline: Int = minBaselineSamples) -> Double? {
        guard let today else { return nil }
        let valid = baseline.compactMap { $0 }
        guard valid.count >= minBaseline else { return nil }
        return today - mean(valid)
    }

    /// z-score backstop for a ~normal series (RHR). nil when SD ~0 or too few samples.
    static func zScore(today: Double?, baselineInput baseline: [Double?], minBaseline: Int = minBaselineSamples) -> Double? {
        guard let today else { return nil }
        let valid = baseline.compactMap { $0 }
        guard valid.count >= minBaseline, let sd = standardDeviation(valid), sd > 1e-6 else { return nil }
        return (today - mean(valid)) / sd
    }

    // MARK: - Acute:chronic strain (§12 G4 — EWMA-decoupled)

    /// EWMA-decoupled acute:chronic workload ratio over whole-day strain.
    /// Uncoupled form (acute EWMA / chronic EWMA, separate decays) avoids the
    /// raw 7:28 autocorrelation flaw. nil when chronic load is ~0 or too sparse.
    ///
    /// `strainSeries` is chronological (oldest → newest); nil days are skipped
    /// (NOT zero-filled — a true rest day with logged 0 strain is a real 0, but a
    /// missing/unsynced day is nil and must not be counted as load).
    static func acuteChronicRatio(
        strainSeries: [Double?],
        acuteDecayDays: Double = 7,
        chronicDecayDays: Double = 28,
        minDays: Int = 14
    ) -> Double? {
        let present = strainSeries.compactMap { $0 }
        guard present.count >= minDays else { return nil }

        let acute = ewma(strainSeries, halfLifeDays: acuteDecayDays)
        let chronic = ewma(strainSeries, halfLifeDays: chronicDecayDays)
        guard let a = acute, let c = chronic, c > 1e-6 else { return nil }
        return a / c
    }

    // MARK: - Primitive math (pure, testable)

    static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample SD (n-1). nil for < 2 samples.
    static func standardDeviation(_ xs: [Double]) -> Double? {
        guard xs.count >= 2 else { return nil }
        let m = mean(xs)
        let variance = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
        return variance.squareRoot()
    }

    /// Simple least-squares slope over x = 0..<n.
    static func slope(_ ys: [Double]) -> Double {
        let n = Double(ys.count)
        guard n >= 2 else { return 0 }
        let xs = (0 ..< ys.count).map(Double.init)
        let mx = mean(xs), my = mean(ys)
        var num = 0.0, den = 0.0
        for i in 0 ..< ys.count {
            num += (xs[i] - mx) * (ys[i] - my)
            den += (xs[i] - mx) * (xs[i] - mx)
        }
        return den > 1e-9 ? num / den : 0
    }

    /// EWMA over a chronological series, skipping nil days (no zero-fill).
    /// halfLifeDays sets the decay: weight = exp(-ln2 * age / halfLife).
    static func ewma(_ series: [Double?], halfLifeDays: Double) -> Double? {
        guard halfLifeDays > 0 else { return nil }
        let lambda = log(2.0) / halfLifeDays
        // Newest sample = age 0. Walk newest→oldest, ages 0,1,2… over CALENDAR
        // position (so a gap correctly ages the older samples).
        var weightedSum = 0.0
        var weightTotal = 0.0
        let n = series.count
        for (idx, value) in series.enumerated() {
            guard let v = value else { continue }
            let age = Double(n - 1 - idx) // newest (last) → 0
            let w = exp(-lambda * age)
            weightedSum += w * v
            weightTotal += w
        }
        return weightTotal > 1e-9 ? weightedSum / weightTotal : nil
    }
}
