import Foundation

// MARK: - Physics of the non-sweat part of weight loss

/// Mass that leaves the body during exercise WITHOUT being sweat, so it must be taken out of a
/// weigh-in before calling the rest "sweat". Two parts:
///
///  1. Respiratory water loss (breathing out humid air).
///     m_e = 0.019 * VO2 * (44 - Pa)  [g/min]   VO2 in L/min STPD, Pa = ambient water vapour pressure in mmHg.
///     Mitchell, Nadel & Stolwijk 1972, J Appl Physiol 32(4):474-476, eq. 3 (read in full), validated on 4 subjects
///     at 30-80% VO2max in dry air (Pa 7-10 mmHg); the data sat 15-20% BELOW eq. 3 at moderate loads, "within 0.25 g/min".
///     Same equation quoted by Maughan, Shirreffs & Leiper 2007, J Sports Sci 25(7):797-804 (read in full).
///
///  2. Net mass lost through gas exchange (more CO2 out than O2 in).
///     m = VO2 * (R * 1.96 - 1.43)  [g/min], R = respiratory quotient, 1.96 and 1.43 g/L = densities of CO2 and O2.
///     Mitchell 1972, eq. 4 (R = 1 gives 0.53 * VO2). Equivalent to Maughan 2007 Table I: carbohydrate -0.40 g per g,
///     fat +0.13 g per g (water of oxidation stays in the body).
///
/// Maughan 2007 writes the whole balance as:
///   sweat = body mass lost + fluid ingested - substrate oxidised + water of oxidation - respiratory water lost
/// and checks it on a marathon example: 3 + 1 - 0.55 + 0.42 - 0.40 = 3.47 L.
struct NonSweatLossEstimate: Sendable, Equatable {
    let kgLow: Double
    let kgMid: Double
    let kgHigh: Double
    /// Standard deviation of the non-sweat loss, kg (range treated as uniform).
    let sigmaKg: Double
    let respiratoryKgMid: Double
    let gasExchangeKgMid: Double
    let notes: [String]
}

enum NonSweatLoss {
    // MARK: Physics constants

    static let respiratoryCoefficient = 0.019 // Mitchell 1972 eq. 3
    static let alveolarVaporPressureMmHg = 44.0 // Mitchell 1972 eq. 3
    static let co2DensityGramsPerLiter = 1.96 // Mitchell 1972
    static let o2DensityGramsPerLiter = 1.43 // Mitchell 1972
    /// Mitchell found measured respiratory loss 15-20% below eq. 3 at moderate loads. We use 0.8...1.0 x eq. 3,
    /// centred on 0.9. This reading of the paper is ours.
    static let respiratoryScale = (low: 0.8, mid: 0.9, high: 1.0)
    /// Mitchell tested water vapour pressures of 7-10 mmHg only.
    static let testedVaporPressureMmHg = 7.0 ... 10.0

    // MARK: Assumptions NOT taken from the papers above (flagged in the output)

    /// Respiratory quotient range during mixed sport. Maughan 2007 Table II shows carbohydrate supplying 30-82% of
    /// the energy as intensity rises; R = 0.85 is mostly-fat mixed, 1.0 is all carbohydrate. Mid is our choice.
    static let respiratoryQuotient = (low: 0.85, mid: 0.92, high: 1.0)
    /// Oxygen to energy: kcal per L O2 = 3.941 + 1.106 * R (Weir 1949, textbook; NOT verified in this session).
    static func kcalPerLiterO2(r: Double) -> Double { 3.941 + 1.106 * r }
    /// How far WHOOP's workout energy may be off. UNVERIFIED assumption (no validation study read).
    static let whoopEnergyError = 0.20
    static let kcalPerKilojoule = 1.0 / 4.184

    // MARK: Weather

    /// Saturation vapour pressure by the Magnus formula (Alduchov & Eskridge 1996 coefficients), hPa -> mmHg.
    static func saturationVaporPressureMmHg(tempC: Double) -> Double {
        let hPa = 6.1094 * exp(17.625 * tempC / (tempC + 243.04))
        return hPa * 0.750062
    }

    static func ambientVaporPressureMmHg(tempC: Double, relativeHumidityPercent: Double) -> Double {
        saturationVaporPressureMmHg(tempC: tempC) * min(max(relativeHumidityPercent, 0), 100) / 100
    }

    // MARK: The two equations

    static func respiratoryWaterGramsPerMinute(vo2LitersPerMinute: Double, vaporPressureMmHg: Double) -> Double {
        max(0, respiratoryCoefficient * vo2LitersPerMinute * (alveolarVaporPressureMmHg - vaporPressureMmHg))
    }

    static func gasExchangeMassLossGramsPerMinute(vo2LitersPerMinute: Double, r: Double) -> Double {
        vo2LitersPerMinute * (r * co2DensityGramsPerLiter - o2DensityGramsPerLiter)
    }

    // MARK: Model

    /// nil when the session has no energy, duration or weather, so the caller falls back to the 5-15% band.
    static func estimate(for session: TrainingSessionSummary) -> NonSweatLossEstimate? {
        guard let kJ = session.kilojoules, kJ > 0, session.durationHours > 0,
              let tempC = session.temperatureC, let rh = session.relativeHumidityPercent
        else { return nil }

        let minutes = session.durationHours * 60
        let kcalPerMin = kJ * kcalPerKilojoule / minutes
        let pa = ambientVaporPressureMmHg(tempC: tempC, relativeHumidityPercent: rh)

        func kg(energyScale: Double, r: Double, respScale: Double) -> (resp: Double, gas: Double) {
            let vo2 = kcalPerMin * energyScale / kcalPerLiterO2(r: r)
            let resp = respiratoryWaterGramsPerMinute(vo2LitersPerMinute: vo2, vaporPressureMmHg: pa) * respScale * minutes / 1000
            let gas = gasExchangeMassLossGramsPerMinute(vo2LitersPerMinute: vo2, r: r) * minutes / 1000
            return (resp, gas)
        }

        let mid = kg(energyScale: 1, r: respiratoryQuotient.mid, respScale: respiratoryScale.mid)
        let lowParts = kg(energyScale: 1 - whoopEnergyError, r: respiratoryQuotient.low, respScale: respiratoryScale.low)
        let highParts = kg(energyScale: 1 + whoopEnergyError, r: respiratoryQuotient.high, respScale: respiratoryScale.high)
        let low = lowParts.resp + lowParts.gas
        let high = highParts.resp + highParts.gas
        let midTotal = mid.resp + mid.gas

        var notes = [
            "Breathing-water loss from Mitchell 1972 and fuel-burn mass from Maughan 2007, using your WHOOP energy and the weather.",
            "WHOOP energy is assumed accurate within 20% (not verified).",
        ]
        if !testedVaporPressureMmHg.contains(pa) {
            notes.append("Mitchell tested dry air only (7-10 mmHg water vapour); today is \(String(format: "%.0f", pa)) mmHg, so the breathing-water term is extrapolated.")
        }
        if session.isIndoor == true { notes.append("Indoor session: using the indoor temperature and humidity you provided.") }

        return NonSweatLossEstimate(kgLow: low, kgMid: midTotal, kgHigh: high, sigmaKg: (high - low) / 12.0.squareRoot(),
                                    respiratoryKgMid: mid.resp, gasExchangeKgMid: mid.gas, notes: notes)
    }

    /// Fallback when the model can't run: the 5-15% share of mass lost (Baker 2017, PMC5371639).
    static func fallbackBand(massLostKg lost: Double) -> NonSweatLossEstimate {
        let share = SweatBalance.nonSweatShare
        return NonSweatLossEstimate(
            kgLow: lost * share.low, kgMid: lost * share.mid, kgHigh: lost * share.high,
            sigmaKg: (share.high - share.low) / 12.0.squareRoot() * lost,
            respiratoryKgMid: 0, gasExchangeKgMid: 0,
            notes: ["No WHOOP energy or weather for this session, so I used the general 5-15% non-sweat share (Baker 2017)."]
        )
    }
}
