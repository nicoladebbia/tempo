import Foundation

// MARK: - Constants with provenance

/// One physiology constant together with where it comes from. `verified` means the
/// number was read in the primary text (not a snippet or secondary summary). The coach
/// shows unverified ones as "estimate" and never as fact.
struct SourcedConstant: Sendable, Equatable {
    let value: Double
    let source: String
    let verified: Bool
}

enum RecoveryConstants {
    // Sweat and body-mass accounting -------------------------------------------------

    /// Share of body-mass loss that is NOT sweat (substrate oxidation + respiratory water).
    /// Baker 2017, Sports Med 47(Suppl 1):111-128 (PMC5371639), read in full: "approximately 5-15% combined".
    static let nonSweatMassLossRange = (low: 0.05, high: 0.15)
    static let nonSweatMassLossSource = "Non-sweat mass: Mitchell 1972 + Maughan 2007 equations when WHOOP energy and weather exist; otherwise Baker 2017 (PMC5371639), 5-15% of mass lost"

    /// Sweat sodium: "averages ~35 mEq/L (range 10-70 mEq/L)" (sodium is monovalent, so mEq/L = mmol/L).
    /// Sawka et al. 2007, ACSM position stand, Med Sci Sports Exerc 39(2):377-390 (read in full); Baker 2017 (PMC5371639)
    /// gives the same 10-70 range.
    static let sweatSodiumMmolPerLiter = (low: 10.0, mid: 35.0, high: 70.0)
    static let sweatSodiumSource = "ACSM 2007 (Sawka): sweat Na+ averages ~35 mEq/L, range 10-70; same range in Baker 2017"
    static let sodiumMgPerMmol = 22.99 // atomic weight of sodium

    // Fluid -------------------------------------------------------------------------

    /// Fluid to drink back as a multiple of the body mass lost: 150%.
    /// Maughan, Leiper & Shirreffs 1996, Eur J Appl Physiol 73:317-325 (PMID 8781863), abstract read in full:
    /// 8 adults dehydrated by 2.1% of body mass drank 150% of the mass lost. With fluid alone (water or a sports drink)
    /// they were still about 0.34-0.37 L net negative 6 h later; with a standard meal plus drink they were back to baseline.
    /// Scope is one small lab study (n = 8, 2.1% loss), so this is a tested dose, not a universal law.
    /// ACSM position stand 2007 (Sawka et al., Med Sci Sports Exerc 39(2):377-390, read in full): "Individuals needing rapid
    /// and complete recovery from excessive dehydration can drink ~1.5 L of fluid for each kilogram of body weight lost",
    /// and "consuming beverages and snacks with sodium will help expedite rapid and complete recovery". Otherwise
    /// "the goal is to replace any fluid electrolyte deficit", and with meals and an 8-12 h recovery "the person should
    /// already be close to being euhydrated".
    static let rehydrationMultiple = SourcedConstant(
        value: 1.5,
        source: "ACSM 2007 (Sawka): ~1.5 L per kg lost for rapid recovery; Maughan 1996 (PMID 8781863): 150% with a meal restored balance",
        verified: true
    )
    /// Without a hard session soon: replace the deficit (1.0 x the mass lost) with normal drinks and meals. ACSM 2007.
    static let rehydrationReplaceOnly = SourcedConstant(value: 1.0, source: "ACSM 2007 (Sawka): replace the fluid deficit; normal meals and drinks over 8-12 h", verified: true)
    /// Rapid recovery window for the fluid rule. ACSM's "protracted recovery period (8-12 h)": we use the upper end.
    static let rapidFluidWindowHours = 12.0

    // Carbohydrate ------------------------------------------------------------------

    /// Rapid glycogen restoration when the next session is < 4 h away: 1.2 g/kg/h (high-GI), or 0.8 g/kg/h carbs + 0.2-0.4 g/kg/h protein.
    /// Kerksick et al. 2017, ISSN nutrient timing position stand (PMC5596471), read in full.
    static let carbPerKgPerHourRapid = SourcedConstant(value: 1.2, source: "Kerksick 2017, ISSN nutrient timing (PMC5596471): 1.2 g/kg/h if < 4 h recovery", verified: true)
    static let carbPerKgPerHourWithProtein = SourcedConstant(value: 0.8, source: "Kerksick 2017 (PMC5596471): 0.8 g/kg/h carbs combined with 0.2-0.4 g/kg/h protein", verified: true)
    /// Very high training load: 8-12 g/kg/day (>= 8 h of exercise per week). Same paper.
    static let dailyCarbVeryHighLoadPerKg = (low: 8.0, high: 12.0)

    // Protein -----------------------------------------------------------------------

    /// Per-dose: 0.25 g/kg or 20-40 g, with 700-3000 mg leucine; spread every 3-4 h. Daily 1.4-2.0 g/kg.
    /// Jäger et al. 2017, ISSN protein position stand (PMC5477153), read in full.
    static let proteinPerDoseGramsPerKg = SourcedConstant(value: 0.25, source: "Jäger 2017, ISSN protein (PMC5477153): 0.25 g/kg per dose", verified: true)
    static let proteinPerDoseAbsoluteGrams = (low: 20.0, high: 40.0)
    static let proteinDailyPerKg = (low: 1.4, high: 2.0)
    static let leucineMgPerDose = (low: 700.0, high: 3000.0)

    // Whoop -------------------------------------------------------------------------

    /// WHOOP's own zone wording is unverified (search snippet only). Used for tone, never for any calculation.
    static let whoopHighStrainFrom = SourcedConstant(value: 14, source: "WHOOP zones per support snippet: High 14-17, All Out 18-21; page not opened", verified: false)
    static let whoopAllOutFrom = SourcedConstant(value: 18, source: "same", verified: false)
}

// MARK: - Output

struct RecoveryPrescription: Sendable, Equatable {
    struct Fluid: Sendable, Equatable {
        /// Sweat as a range: the raw weigh-in overstates sweat by the non-sweat share.
        let sweatLitersLow: Double
        let sweatLitersHigh: Double
        /// Liters of fluid to drink over the next hours: the body mass lost times the rehydration multiple.
        let drinkLiters: Double
        /// Sodium lost in sweat, mg, as a range (concentration range x sweat range).
        let sodiumMgLow: Double
        let sodiumMgHigh: Double
        /// Sodium to put back (planning value, midpoint concentration), mg.
        let sodiumMgPlan: Double
    }

    struct Macros: Sendable, Equatable {
        let carbsGrams: Double
        let proteinGrams: Double
        let proteinLeucineMgLow: Double
        let proteinLeucineMgHigh: Double
        /// Hours over which the carbs are spread (4 when rapid recovery is needed).
        let carbWindowHours: Double
    }

    let fluid: Fluid?
    let macros: Macros
    /// One line per number saying where it comes from; unverified ones are marked "estimate".
    let evidenceNotes: [String]
    /// Plain-language reasons, in the order the coach should say them.
    let reasons: [String]
}

// MARK: - Builder

/// Turns a finished session + sweat estimate into "drink this, eat this" with the evidence
/// behind every number. Pure and deterministic. It claims no more than the data allows:
/// without a measured sweat estimate there is NO fluid or sodium advice, only macros.
enum RecoveryPlanner {
    /// - Parameters:
    ///   - bodyMassKg: current body mass (use the pre-session weigh-in when you have it).
    ///   - hoursUntilNextHardSession: nil means no hard session soon. < 4 triggers the rapid-refuel plan.
    static func prescribe(
        session: TrainingSessionSummary,
        sweat: SweatEstimate,
        bodyMassKg: Double,
        hoursUntilNextHardSession: Double? = nil
    ) -> RecoveryPrescription {
        var reasons: [String] = []
        var evidence: [String] = []

        // --- Fluid and sodium: only with a MEASURED sweat estimate.
        var fluid: RecoveryPrescription.Fluid?
        if sweat.quality == .measured, let lost = sweat.massLostKg,
           let sweatLow = sweat.sweatLitersLow, let sweatHigh = sweat.sweatLitersHigh
        {
            // The rehydration rule applies to the body mass actually lost, so it is NOT reduced by the
            // non-sweat share (that adjustment is only for the sweat and sodium estimate).
            let rapidFluid = (hoursUntilNextHardSession ?? 0) < RecoveryConstants.rapidFluidWindowHours
            let mult = rapidFluid ? RecoveryConstants.rehydrationMultiple.value : RecoveryConstants.rehydrationReplaceOnly.value

            let sodium = RecoveryConstants.sweatSodiumMmolPerLiter
            let mg = RecoveryConstants.sodiumMgPerMmol
            fluid = RecoveryPrescription.Fluid(
                sweatLitersLow: sweatLow,
                sweatLitersHigh: sweatHigh,
                drinkLiters: lost * mult,
                sodiumMgLow: sweatLow * sodium.low * mg,
                sodiumMgHigh: sweatHigh * sodium.high * mg,
                sodiumMgPlan: (sweatLow + sweatHigh) / 2 * sodium.mid * mg
            )
            reasons.append("You lost \(fmt(lost)) kg over \(fmt(session.durationHours)) h, so about \(fmt(sweatLow))-\(fmt(sweatHigh)) L of that was sweat.")
            evidence.append(RecoveryConstants.nonSweatMassLossSource)
            evidence.append(RecoveryConstants.sweatSodiumSource)
            if let u = sweat.uncertainty { evidence.append("Sweat estimate is +/-\(String(format: "%.0f", u.relativeError95Percent))% (95%): " + u.assumptions.joined(separator: " ")) }
            evidence.append(RecoveryConstants.rehydrationMultiple.source)
            reasons.append(rapidFluid
                ? "Another hard session may come within \(Int(RecoveryConstants.rapidFluidWindowHours)) hours (or I don't know when), so drink 1.5 L per kg lost (ACSM)."
                : "No hard session within \(Int(RecoveryConstants.rapidFluidWindowHours)) hours, so replacing what you lost with normal drinks and meals is enough (ACSM).")
            reasons.append("Drink it with a meal that has salt and potassium. In a lab study, water alone at 150% still left people about 0.35 L short six hours later, while water with a meal restored balance.")
        } else {
            reasons.append("No usable weigh-in around this session, so I'm not giving fluid or sodium numbers. Weigh yourself to unlock them.")
        }

        // --- Carbohydrate
        let rapid = (hoursUntilNextHardSession ?? .infinity) < 4
        let carbs: Double
        let window: Double
        if rapid {
            carbs = RecoveryConstants.carbPerKgPerHourRapid.value * bodyMassKg * 4
            window = 4
            reasons.append("Another hard session is under 4 hours away, so refuel fast: \(fmt(RecoveryConstants.carbPerKgPerHourRapid.value)) g of carbs per kg every hour.")
            evidence.append(RecoveryConstants.carbPerKgPerHourRapid.source)
        } else {
            // No rapid window: normal daily intake covers glycogen (Kerksick 2017); give a sensible first meal, not a formula claim.
            carbs = RecoveryConstants.carbPerKgPerHourWithProtein.value * bodyMassKg * 2
            window = 2
            reasons.append("No hard session soon, so timing matters less: a carb-rich meal in the next 2 hours is enough, then normal meals.")
            evidence.append(RecoveryConstants.carbPerKgPerHourWithProtein.source)
        }

        // --- Protein: one dose.
        let perDose = RecoveryConstants.proteinPerDoseGramsPerKg.value * bodyMassKg
        let range = RecoveryConstants.proteinPerDoseAbsoluteGrams
        let protein = min(max(perDose, range.low), range.high)
        reasons.append("Protein: about \(Int(protein.rounded())) g in one go (0.25 g per kg, kept inside 20-40 g).")
        evidence.append(RecoveryConstants.proteinPerDoseGramsPerKg.source)

        let leucine = RecoveryConstants.leucineMgPerDose
        return RecoveryPrescription(
            fluid: fluid,
            macros: .init(carbsGrams: carbs, proteinGrams: protein, proteinLeucineMgLow: leucine.low, proteinLeucineMgHigh: leucine.high, carbWindowHours: window),
            evidenceNotes: evidence,
            reasons: reasons
        )
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}


// MARK: - What sweat carries besides water and sodium

/// Average and range of electrolytes in sweat, mEq/L. Sawka et al. 2007, ACSM position stand (read in full), citing ref. 17.
/// These exist so the coach can say HOW MUCH you really lost: for magnesium it is tiny next to the daily need.
enum SweatElectrolytes {
    struct Level: Sendable, Equatable {
        let low: Double
        let mean: Double
        let high: Double
        let mgPerMEq: Double // milligrams per milliequivalent (atomic weight / charge)

        func milligrams(sweatLiters: Double) -> (low: Double, mean: Double, high: Double) {
            (low * mgPerMEq * sweatLiters, mean * mgPerMEq * sweatLiters, high * mgPerMEq * sweatLiters)
        }
    }

    static let potassium = Level(low: 3, mean: 5, high: 15, mgPerMEq: 39.098)
    static let calcium = Level(low: 0.3, mean: 1, high: 2, mgPerMEq: 20.039)
    static let magnesium = Level(low: 0.2, mean: 0.8, high: 1.5, mgPerMEq: 12.153)
    static let chloride = Level(low: 5, mean: 30, high: 60, mgPerMEq: 35.453)
    static let source = "ACSM 2007 (Sawka): sweat K+ 5 (3-15), Ca2+ 1 (0.3-2), Mg2+ 0.8 (0.2-1.5), Cl- 30 (5-60) mEq/L"
}
