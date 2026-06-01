//
// HydrationMath.swift
// Tempo
//

import Foundation

// MARK: - HydrationMath

/// Single source of truth for activity-driven sweat-loss → hydration math.
/// Shared by `NutritionEngine` (to set the day's hydration target) and the
/// training surfaces (to show a per-session "you lost ~X L" readout) so the
/// two can never disagree.
///
/// The estimate is deliberately ROUGH and must be presented as a range, never
/// a false-precise single figure — without pre/post body-weight measurement,
/// sweat loss is an approximation (±~20%).
enum HydrationMath {
    // MARK: Constants (stated assumptions, not gospel — back-of-envelope sports science)

    /// Heat dissipated by evaporating 1 L of sweat (kcal). Standard physiology
    /// value (~580 kcal/L at skin temperature).
    private static let kcalPerLitreSweat: Double = 580

    /// Fraction of exercise energy expenditure that becomes heat the body must
    /// shed (the rest is mechanical work). ~70–80%; we use the midpoint.
    private static let heatFraction: Double = 0.75

    /// Estimate-uncertainty band applied to produce a displayed range.
    private static let errorBand: Double = 0.20

    /// Max fluid the body can absorb / safely replace per hour (L). The
    /// "not too much" guardrail — over-replacement risks hyponatremia and
    /// exceeds gastric absorption.
    private static let maxReplaceLitresPerHour: Double = 1.0

    /// Above this loss, plain water isn't enough — recommend electrolytes.
    static let electrolyteThresholdLitres: Double = 1.0

    // MARK: API

    /// Estimated sweat loss as a range (low...high litres) for an activity.
    /// `weatherFactor` lets heat/humidity scale the estimate later (1.0 = no
    /// adjustment, the only value available until WeatherKit is wired).
    /// Returns nil when there's no usable calorie signal (e.g. manual log).
    static func sweatLossLitres(
        caloriesBurned: Double?,
        durationMinutes: Double?,
        weatherFactor: Double = 1.0
    ) -> ClosedRange<Double>? {
        guard let cal = caloriesBurned, cal > 0 else {
            return nil // manual attestation / no metrics — nothing to estimate
        }

        let raw = (cal * heatFraction) / kcalPerLitreSweat * weatherFactor

        // Safety cap: never imply replacing faster than the body can absorb.
        let capped: Double
        if let mins = durationMinutes, mins > 0 {
            capped = min(raw, maxReplaceLitresPerHour * (mins / 60.0))
        } else {
            capped = raw
        }

        let low = capped * (1 - errorBand)
        let high = capped * (1 + errorBand)
        return low ... high
    }

    /// Added hydration (ml) to fold into the day's target for a logged
    /// activity. Uses the conservative LOW end of the sweat range (per the
    /// user's "not too much" intent) so the daily target never over-prescribes.
    /// Returns 0 when there's no usable estimate.
    static func activityBonusMl(
        caloriesBurned: Double?,
        durationMinutes: Double?,
        weatherFactor: Double = 1.0
    ) -> Int {
        guard let range = sweatLossLitres(
            caloriesBurned: caloriesBurned,
            durationMinutes: durationMinutes,
            weatherFactor: weatherFactor
        ) else {
            return 0
        }
        return Int((range.lowerBound * 1000).rounded())
    }

    /// Whether a loss of this size warrants electrolytes, not just water.
    static func needsElectrolytes(_ litres: Double) -> Bool {
        litres >= electrolyteThresholdLitres
    }
}
