import Foundation

// MARK: - Inputs

/// One body-weight reading, from the Withings scale (via Apple Health) or typed by hand.
struct WeighIn: Sendable, Equatable, Codable {
    enum Source: String, Sendable, Codable { case withings, manual }

    let time: Date
    let kg: Double
    let source: Source
}

/// What the coach needs to know about a finished session. Strain, heart-rate
/// zones and energy come from Whoop; the weather is optional.
struct TrainingSessionSummary: Sendable, Equatable {
    let start: Date
    let end: Date
    let sport: String
    let strain: Double? // Whoop scale 0...21
    let kilojoules: Double? // Whoop workout energy
    let averageHeartRate: Int?
    let temperatureC: Double?
    let relativeHumidityPercent: Double?
    let isIndoor: Bool?

    var durationHours: Double { max(0, end.timeIntervalSince(start)) / 3600 }
}

/// Fluid the athlete reports having drunk, and urine passed, during the session.
/// Both are optional: if unknown, the sweat figure is a MINIMUM (see `SweatEstimate.isLowerBound`).
struct SessionFluids: Sendable, Equatable {
    var drankLiters: Double?
    var urineLiters: Double?
}

/// How precise the scale is. Resolution = smallest step it displays; repeatability = the
/// standard deviation of repeated readings of the same weight.
/// Resolution default 0.05 kg: Withings support FAQ "Body Comp - Frequently asked questions" (updated Sept 2023, read in
/// full): "Measurements are precise up to 0.1 lbs (.05 kg)", "up to 50 g (vs 100 g for Body+ and Body Cardio)". That is the
/// stated precision, NOT a measured repeatability. Repeatability default 0.05 kg is an ASSUMPTION: replace it with the
/// user's own measured repeatability from `ScaleCalibration`.
struct ScaleSpec: Sendable, Equatable {
    var resolutionKg: Double = 0.05
    var repeatabilitySDKg: Double = 0.05
    var isMeasured: Bool = false

    /// Standard deviation of one reading: display rounding (uniform) combined with repeatability.
    var readingSDKg: Double {
        let rounding = resolutionKg / 12.0.squareRoot()
        return (rounding * rounding + repeatabilitySDKg * repeatabilitySDKg).squareRoot()
    }
}

/// Turns repeated weigh-ins of an unchanged body (e.g. three readings in a row) into a measured `ScaleSpec`.
enum ScaleCalibration {
    /// Needs at least 3 readings; returns nil otherwise. Repeatability is the sample standard deviation.
    static func spec(fromRepeatedReadingsKg readings: [Double], resolutionKg: Double = 0.1) -> ScaleSpec? {
        guard readings.count >= 3 else { return nil }
        let mean = readings.reduce(0, +) / Double(readings.count)
        let variance = readings.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(readings.count - 1)
        return ScaleSpec(resolutionKg: resolutionKg, repeatabilitySDKg: variance.squareRoot(), isMeasured: true)
    }
}

// MARK: - Output

struct SweatUncertainty: Sendable, Equatable {
    /// Standard deviation of the sweat estimate, liters.
    let sigmaLiters: Double
    /// Half-width of the 95% interval as a percentage of the sweat estimate.
    let relativeError95Percent: Double
    /// True only when the 95% interval is within +/-5%. With a weigh-in alone this is out of reach
    /// (the non-sweat band alone is about +/-6%), so the app must show the +/- and never claim 5%.
    let meetsFivePercentTarget: Bool
    /// Every assumption the figure rests on, user-readable.
    let assumptions: [String]
}

struct SweatEstimate: Sendable, Equatable {
    enum Quality: String, Sendable {
        /// Pre AND post weigh-in found close to the session.
        case measured
        /// A weigh-in is missing or too far from the session: no number is claimed.
        case needsWeighIn
        /// The readings disagree with physiology (e.g. weight went UP, or an implausible loss): ask the user to re-weigh.
        case implausible
    }

    /// `tight` = both weigh-ins within 30 minutes of the session (little room for unrecorded drinking, eating, toilet).
    enum Tightness: String, Sendable { case tight, loose }

    let quality: Quality
    let protocolQuality: Tightness?
    let pre: WeighIn?
    let post: WeighIn?
    /// Body-mass change over the session in kg (positive = lost weight). nil unless measured.
    let massLostKg: Double?
    /// body-mass lost + fluid drunk - urine, BEFORE removing the non-sweat share. Overstates sweat; use the range below.
    let sweatLitersRaw: Double?
    /// Sweat after removing the non-sweat share of mass loss (5-15%, Baker 2017). Low/high/mid in liters.
    let sweatLitersLow: Double?
    let sweatLitersMid: Double?
    let sweatLitersHigh: Double?
    /// Percent of starting body mass lost. nil unless measured.
    let percentBodyMassLost: Double?
    /// True when fluid intake was not provided: real sweat is then AT LEAST this much.
    let isLowerBound: Bool
    let uncertainty: SweatUncertainty?
    /// Short, user-readable caveats the UI should show (never hidden).
    let notes: [String]
}

// MARK: - Calculator

/// Turns weigh-ins around a session into a sweat estimate, and is deliberately
/// strict about when it refuses to give a number. Pure and deterministic.
enum SweatBalance {
    /// How far before the start the "pre" weigh-in may be, and how long after the end the "post" one may be.
    static let preWindow: TimeInterval = 3 * 3600
    static let postWindow: TimeInterval = 2 * 3600
    /// WHOOP detects start/end of a workout automatically and can be a few minutes off. A pre weigh-in a little
    /// AFTER the recorded start, or a post weigh-in a little BEFORE the recorded end, still counts.
    static let detectionSlack: TimeInterval = 10 * 60
    /// Both weigh-ins this close to the session = `tight` protocol.
    static let tightWindow: TimeInterval = 30 * 60

    /// Largest plausible loss in one session, as a share of body mass. Above it we ask for a re-weigh.
    /// Editorial guard: published sweat losses above ~4% of body mass are rare and often a scale or clothing error.
    static let implausibleLossFraction = 0.04

    /// Non-sweat share of body-mass loss (substrate oxidation + respiratory water): 5-15%, Baker 2017 (PMC5371639).
    static let nonSweatShare = (low: 0.05, mid: 0.10, high: 0.15)

    /// Picks the latest weigh-in in `[start - preWindow, start + slack]` and the earliest in `[end - slack, end + postWindow]`.
    static func pair(weighIns: [WeighIn], for session: TrainingSessionSummary) -> (pre: WeighIn?, post: WeighIn?) {
        let pre = weighIns
            .filter { $0.time <= session.start.addingTimeInterval(detectionSlack) && $0.time >= session.start.addingTimeInterval(-preWindow) }
            .max { $0.time < $1.time }
        let post = weighIns
            .filter { $0.time >= session.end.addingTimeInterval(-detectionSlack) && $0.time <= session.end.addingTimeInterval(postWindow) }
            .min { $0.time < $1.time }
        return (pre, post)
    }

    static func estimate(
        session: TrainingSessionSummary,
        weighIns: [WeighIn],
        fluids: SessionFluids = SessionFluids(),
        scale: ScaleSpec = ScaleSpec()
    ) -> SweatEstimate {
        let (pre, post) = pair(weighIns: weighIns, for: session)

        guard let pre, let post, post.time > pre.time else {
            var notes: [String] = []
            if pre == nil { notes.append("No weigh-in in the 3 hours before the session.") }
            if post == nil { notes.append("No weigh-in in the 2 hours after the session.") }
            if let pre, let post, post.time <= pre.time {
                notes.append("The weigh-ins overlap each other: weigh in before the session starts and again after it ends.")
            }
            return empty(.needsWeighIn, pre: pre, post: post, notes: notes)
        }

        let lost = pre.kg - post.kg
        let percent = pre.kg > 0 ? lost / pre.kg * 100 : 0

        if lost < 0 || percent > implausibleLossFraction * 100 {
            let why = lost < 0
                ? "You weigh more after the session than before. Re-weigh with the same clothes and after the toilet."
                : "A loss of \(String(format: "%.1f", percent))% in one session is unusually high. Check the scale and clothing."
            return SweatEstimate(quality: .implausible, protocolQuality: nil, pre: pre, post: post, massLostKg: lost,
                                 sweatLitersRaw: nil, sweatLitersLow: nil, sweatLitersMid: nil, sweatLitersHigh: nil,
                                 percentBodyMassLost: percent, isLowerBound: false, uncertainty: nil, notes: [why])
        }

        // 1 kg of body mass ~ 1 L of sweat once fluid in and urine out are accounted for.
        let drank = fluids.drankLiters ?? 0
        let urine = fluids.urineLiters ?? 0
        let raw = max(0, lost + drank - urine)
        // Take the non-sweat part out: physics model (WHOOP energy + weather) when possible, else the 5-15% band.
        let nonSweat = NonSweatLoss.estimate(for: session) ?? NonSweatLoss.fallbackBand(massLostKg: lost)
        let low = max(0, raw - nonSweat.kgHigh)
        let mid = max(0, raw - nonSweat.kgMid)
        let high = max(0, raw - nonSweat.kgLow)
        let lowerBound = fluids.drankLiters == nil

        let gapBefore = session.start.timeIntervalSince(pre.time)
        let gapAfter = post.time.timeIntervalSince(session.end)
        let tight = abs(gapBefore) <= tightWindow && abs(gapAfter) <= tightWindow
        let protocolQuality: SweatEstimate.Tightness = tight ? .tight : .loose

        var notes: [String] = []
        if lowerBound { notes.append("Fluid drunk during the session wasn't entered, so real sweat is at least this much.") }
        if fluids.urineLiters == nil { notes.append("Assuming no urine during the session.") }
        if pre.source != post.source { notes.append("The two weigh-ins came from different scales (\(pre.source.rawValue), \(post.source.rawValue)); a small offset is possible.") }
        if !tight {
            notes.append("A weigh-in was more than 30 minutes from the session. Anything you ate, drank or flushed in between is missing from this number.")
        }
        notes.append(contentsOf: nonSweat.notes)
        notes.append("Weigh in the same clothes (or none), towel-dry, after the toilet, and before drinking.")

        let uncertainty = uncertainty(lost: lost, mid: mid, nonSweatSigma: nonSweat.sigmaKg, drank: fluids.drankLiters,
                                      urine: fluids.urineLiters, scale: scale, lowerBound: lowerBound)

        return SweatEstimate(quality: .measured, protocolQuality: protocolQuality, pre: pre, post: post, massLostKg: lost,
                             sweatLitersRaw: raw, sweatLitersLow: low, sweatLitersMid: mid, sweatLitersHigh: high,
                             percentBodyMassLost: percent, isLowerBound: lowerBound, uncertainty: uncertainty, notes: notes)
    }

    // MARK: Error budget

    /// Independent error sources, combined in quadrature:
    ///  1. the two scale readings (rounding + repeatability);
    ///  2. the unknown non-sweat share, uniform on 5-15% of the mass lost (Baker 2017);
    ///  3. the user's own estimate of fluid drunk and urine, assumed +/-10% of the volume (ASSUMPTION).
    /// When fluid intake is unknown the estimate is a lower bound and no relative error is claimed.
    static func uncertainty(lost: Double, mid: Double, nonSweatSigma: Double? = nil, drank: Double?, urine: Double?, scale: ScaleSpec, lowerBound: Bool) -> SweatUncertainty? {
        guard mid > 0 else { return nil }
        let scaleSD = 2.0.squareRoot() * scale.readingSDKg
        let nonSweatSD = nonSweatSigma ?? (nonSweatShare.high - nonSweatShare.low) / 12.0.squareRoot() * lost
        let volumeError = 0.10
        let drankSD = (drank ?? 0) * volumeError / 3.0.squareRoot()
        let urineSD = (urine ?? 0) * volumeError / 3.0.squareRoot()
        let sd = (scaleSD * scaleSD + nonSweatSD * nonSweatSD + drankSD * drankSD + urineSD * urineSD).squareRoot()
        let rel95 = 1.96 * sd / mid * 100

        var assumptions = [
            nonSweatSigma == nil
                ? "Non-sweat share of weight loss is 5-15% (Baker 2017)."
                : "Breathing-water and fuel-burn mass modelled from WHOOP energy and weather (Mitchell 1972, Maughan 2007).",
            scale.isMeasured
                ? "Scale repeatability measured on your own scale: \(String(format: "%.3f", scale.repeatabilitySDKg)) kg."
                : "Scale precision is assumed (0.05 kg steps per Withings, 0.05 kg repeatability), not measured on your scale.",
        ]
        if drank != nil { assumptions.append("Your fluid estimate is assumed within 10% of the true amount.") }
        return SweatUncertainty(sigmaLiters: sd, relativeError95Percent: rel95,
                                meetsFivePercentTarget: !lowerBound && rel95 <= 5, assumptions: assumptions)
    }

    private static func empty(_ q: SweatEstimate.Quality, pre: WeighIn?, post: WeighIn?, notes: [String]) -> SweatEstimate {
        SweatEstimate(quality: q, protocolQuality: nil, pre: pre, post: post, massLostKg: nil, sweatLitersRaw: nil,
                      sweatLitersLow: nil, sweatLitersMid: nil, sweatLitersHigh: nil, percentBodyMassLost: nil,
                      isLowerBound: false, uncertainty: nil, notes: notes)
    }
}
