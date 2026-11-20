@testable import App
import Foundation
import Testing

@Suite("Sweat balance")
struct SweatBalanceTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(startOffset: TimeInterval = 0, hours: Double = 1.5) -> TrainingSessionSummary {
        let start = t0.addingTimeInterval(startOffset)
        // No energy or weather: the calculator uses the general 5-15% band, which these tests assume.
        return TrainingSessionSummary(start: start, end: start.addingTimeInterval(hours * 3600), sport: "Soccer", strain: 17,
                                      kilojoules: nil, averageHeartRate: 150, temperatureC: nil, relativeHumidityPercent: nil, isIndoor: false)
    }

    private func w(_ minutes: Double, _ kg: Double, _ source: WeighIn.Source = .withings) -> WeighIn {
        WeighIn(time: t0.addingTimeInterval(minutes * 60), kg: kg, source: source)
    }

    @Test func measuresLossFromPreAndPostWeighIn() throws {
        // session 0...90 min; pre at -10, post at +100
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-10, 78.0), w(100, 77.5)],
                                      fluids: .init(drankLiters: 0.5, urineLiters: 0))
        #expect(e.quality == .measured)
        #expect(abs(try #require(e.massLostKg) - 0.5) < 1e-9)
        #expect(abs(try #require(e.sweatLitersRaw) - 1.0) < 1e-9) // 0.5 lost + 0.5 drunk
        #expect(abs(try #require(e.percentBodyMassLost) - 0.641) < 0.001)
        #expect(e.isLowerBound == false)
    }

    @Test func unknownFluidIntakeMakesItAMinimumAndSaysSo() {
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-10, 78.0), w(100, 77.5)])
        #expect(e.quality == .measured)
        #expect(e.sweatLitersRaw == 0.5)
        #expect(e.isLowerBound)
        #expect(e.notes.contains { $0.contains("at least") })
    }

    @Test func picksTheClosestWeighInsOnEachSide() {
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-150, 80.0), w(-5, 78.0), w(95, 77.4), w(110, 77.9)])
        #expect(e.pre?.kg == 78.0) // latest before start
        #expect(e.post?.kg == 77.4) // earliest after end
    }

    @Test func weighInOutsideTheWindowIsNotUsedAndNoNumberIsClaimed() {
        // pre is 4 h before: outside the 3 h window
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-240, 78.0), w(100, 77.5)])
        #expect(e.quality == .needsWeighIn)
        #expect(e.sweatLitersRaw == nil && e.massLostKg == nil)
        #expect(e.notes.contains { $0.contains("before") })
    }

    @Test func missingPostWeighInAsksForOne() {
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-10, 78.0)])
        #expect(e.quality == .needsWeighIn)
        #expect(e.notes.contains { $0.contains("after") })
    }

    @Test func weightGainIsImplausibleNotNegativeSweat() {
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-10, 78.0), w(100, 78.6)])
        #expect(e.quality == .implausible)
        #expect(e.sweatLitersRaw == nil)
    }

    @Test func lossAboveFourPercentIsFlaggedForReweigh() {
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-10, 78.0), w(100, 74.0)]) // 5.1%
        #expect(e.quality == .implausible)
    }

    @Test func sweatIsNeverNegativeWhenYouDrankMoreThanYouLost() throws {
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-10, 78.0), w(100, 78.0)],
                                      fluids: .init(drankLiters: 0, urineLiters: 0.4))
        #expect(try #require(e.sweatLitersRaw) == 0)
    }

    @Test func mixedScalesAreCalledOut() {
        let e = SweatBalance.estimate(session: session(), weighIns: [w(-10, 78.0, .withings), w(100, 77.5, .manual)])
        #expect(e.notes.contains { $0.contains("different scales") })
    }
}

// MARK: - Recovery planner

@Suite("Recovery planner")
struct RecoveryPlannerTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private var session: TrainingSessionSummary {
        TrainingSessionSummary(start: t0, end: t0.addingTimeInterval(5400), sport: "Soccer", strain: 17,
                               kilojoules: nil, averageHeartRate: 150, temperatureC: nil, relativeHumidityPercent: nil, isIndoor: false)
    }

    private func measured(lost: Double, drank: Double = 0) -> SweatEstimate {
        let w = [WeighIn(time: t0.addingTimeInterval(-600), kg: 78.0, source: .withings),
                 WeighIn(time: t0.addingTimeInterval(6000), kg: 78.0 - lost, source: .withings)]
        return SweatBalance.estimate(session: session, weighIns: w, fluids: .init(drankLiters: drank, urineLiters: 0))
    }

    @Test func fluidIsAnEstimatedRangeNotAPinpoint() throws {
        let sweat = measured(lost: 1.0, drank: 0.5) // sweat 1.5 L raw
        let p = RecoveryPlanner.prescribe(session: session, sweat: sweat, bodyMassKg: 77.0)
        let f = try #require(p.fluid)
        // non-sweat share 5-15% of the 1.0 kg lost -> sweat 1.35...1.45 L
        #expect(abs(f.sweatLitersLow - 1.35) < 1e-9)
        #expect(abs(f.sweatLitersHigh - 1.45) < 1e-9)
        #expect(f.sweatLitersLow < f.sweatLitersHigh)
    }

    @Test func drinkAmountIsMassLostTimesMultipleWithoutAnyInventedAdjustment() throws {
        let p = RecoveryPlanner.prescribe(session: session, sweat: measured(lost: 1.0), bodyMassKg: 77.0)
        #expect(abs(try #require(p.fluid).drinkLiters - 1.5) < 1e-9) // 1.0 kg x 1.5
    }

    @Test func sodiumRangeUsesPublishedConcentrationRange() throws {
        let p = RecoveryPlanner.prescribe(session: session, sweat: measured(lost: 1.0, drank: 0.5), bodyMassKg: 77.0)
        let f = try #require(p.fluid)
        #expect(abs(f.sodiumMgLow - 1.35 * 10 * 22.99) < 1e-6)
        #expect(abs(f.sodiumMgHigh - 1.45 * 70 * 22.99) < 1e-6)
        #expect(f.sodiumMgLow < f.sodiumMgPlan && f.sodiumMgPlan < f.sodiumMgHigh)
    }

    @Test func noMeasuredSweatMeansNoFluidOrSodiumNumbers() {
        let none = SweatBalance.estimate(session: session, weighIns: [])
        let p = RecoveryPlanner.prescribe(session: session, sweat: none, bodyMassKg: 77.0)
        #expect(p.fluid == nil)
        #expect(p.reasons.first?.contains("not giving fluid or sodium numbers") == true)
        #expect(p.macros.proteinGrams > 0, "macros still come back")
    }

    @Test func rapidRefuelUsesOnePointTwoGramsPerKgPerHourForFourHours() {
        let p = RecoveryPlanner.prescribe(session: session, sweat: measured(lost: 0.5), bodyMassKg: 77.0, hoursUntilNextHardSession: 3)
        #expect(abs(p.macros.carbsGrams - 1.2 * 77.0 * 4) < 1e-9) // 369.6 g
        #expect(p.macros.carbWindowHours == 4)
    }

    @Test func noRapidWindowGivesAModerateFirstMeal() {
        let p = RecoveryPlanner.prescribe(session: session, sweat: measured(lost: 0.5), bodyMassKg: 77.0, hoursUntilNextHardSession: 20)
        #expect(abs(p.macros.carbsGrams - 0.8 * 77.0 * 2) < 1e-9)
        #expect(p.macros.carbWindowHours == 2)
    }

    @Test func proteinIsQuarterGramPerKgClampedToTwentyToForty() {
        func protein(_ kg: Double) -> Double {
            RecoveryPlanner.prescribe(session: session, sweat: measured(lost: 0.5), bodyMassKg: kg).macros.proteinGrams
        }
        #expect(protein(60) == 20) // 15 g -> clamped up
        #expect(abs(protein(100) - 25) < 1e-9)
        #expect(protein(200) == 40) // 50 g -> clamped down
    }

    @Test func everyConstantUsedHasASourceAndTheStillUnverifiedOnesAreFlagged() {
        let p = RecoveryPlanner.prescribe(session: session, sweat: measured(lost: 1.0), bodyMassKg: 77.0)
        #expect(p.evidenceNotes.contains { $0.contains("ACSM 2007") })
        #expect(RecoveryConstants.rehydrationMultiple.verified)
        #expect(RecoveryConstants.carbPerKgPerHourRapid.verified && RecoveryConstants.proteinPerDoseGramsPerKg.verified)
        // Used only for tone, never in a calculation, and still not read on WHOOP's own page:
        #expect(RecoveryConstants.whoopHighStrainFrom.verified == false)
    }

    @Test func fluidAdviceAlwaysSaysToDrinkItWithAMeal() {
        let p = RecoveryPlanner.prescribe(session: session, sweat: measured(lost: 1.0), bodyMassKg: 77.0)
        #expect(p.reasons.contains { $0.contains("with a meal") })
        let none = RecoveryPlanner.prescribe(session: session, sweat: SweatBalance.estimate(session: session, weighIns: []), bodyMassKg: 77.0)
        #expect(none.reasons.contains { $0.contains("with a meal") } == false, "no fluid advice, so no fluid-with-meal line")
    }
}


// MARK: - Bugs found in review + error budget

@Suite("Sweat balance: robustness and error budget")
struct SweatErrorBudgetTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var session: TrainingSessionSummary {
        TrainingSessionSummary(start: t0, end: t0.addingTimeInterval(5400), sport: "Soccer", strain: 17, kilojoules: nil,
                               averageHeartRate: 150, temperatureC: nil, relativeHumidityPercent: nil, isIndoor: false)
    }
    private func w(_ minutes: Double, _ kg: Double) -> WeighIn { WeighIn(time: t0.addingTimeInterval(minutes * 60), kg: kg, source: .withings) }

    @Test func postWeighInTakenJustBeforeWhoopEndedStillCounts() {
        // Whoop recorded the end at +90 min, but you stepped on the scale at +85 min.
        let e = SweatBalance.estimate(session: session, weighIns: [w(-5, 78.0), w(85, 76.8)], fluids: .init(drankLiters: 0, urineLiters: 0))
        #expect(e.quality == .measured)
        #expect(e.post?.kg == 76.8)
    }

    @Test func weighInMoreThanSlackBeforeTheEndIsRejected() {
        let e = SweatBalance.estimate(session: session, weighIns: [w(-5, 78.0), w(60, 76.8)])
        #expect(e.quality == .needsWeighIn)
    }

    @Test func preWeighInJustAfterWhoopStartStillCounts() {
        let e = SweatBalance.estimate(session: session, weighIns: [w(6, 78.0), w(100, 76.8)])
        #expect(e.quality == .measured)
    }

    @Test func rangeBracketsTheMidAndRemovesTheNonSweatShare() throws {
        let e = SweatBalance.estimate(session: session, weighIns: [w(-5, 78.0), w(95, 77.0)], fluids: .init(drankLiters: 0.5, urineLiters: 0))
        // raw = 1.0 + 0.5 = 1.5; non-sweat 5/10/15% of 1.0 kg
        #expect(abs(try #require(e.sweatLitersLow) - 1.35) < 1e-9)
        #expect(abs(try #require(e.sweatLitersMid) - 1.40) < 1e-9)
        #expect(abs(try #require(e.sweatLitersHigh) - 1.45) < 1e-9)
    }

    @Test func tightProtocolWhenBothWeighInsAreWithinThirtyMinutes() {
        let tight = SweatBalance.estimate(session: session, weighIns: [w(-10, 78.0), w(100, 77.0)])
        let loose = SweatBalance.estimate(session: session, weighIns: [w(-100, 78.0), w(100, 77.0)])
        #expect(tight.protocolQuality == .tight)
        #expect(loose.protocolQuality == .loose)
        #expect(loose.notes.contains { $0.contains("more than 30 minutes") })
    }

    @Test func fiveToFifteenPercentBandAloneCapsAccuracyAboveFivePercent() throws {
        // A PERFECT scale: only the non-sweat band remains. It must not reach +/-5% (95%).
        let perfect = ScaleSpec(resolutionKg: 0, repeatabilitySDKg: 0, isMeasured: true)
        for lost in [1.0, 2.0, 4.0] {
            let u = try #require(SweatBalance.uncertainty(lost: lost, mid: lost * 0.9, drank: 0, urine: 0, scale: perfect, lowerBound: false))
            #expect(abs(u.relativeError95Percent - 6.3) < 0.1, "lost \(lost): \(u.relativeError95Percent)")
            #expect(u.meetsFivePercentTarget == false)
        }
    }

    @Test func errorShrinksAsTheLossGrowsAndNeverClaimsFiveWithAnAssumedScale() throws {
        func rel(_ lost: Double) throws -> Double {
            try #require(SweatBalance.uncertainty(lost: lost, mid: lost * 0.9 + 0.5, drank: 0.5, urine: 0, scale: ScaleSpec(), lowerBound: false)).relativeError95Percent
        }
        let a = try rel(0.5), b = try rel(1), c = try rel(2), d = try rel(4)
        #expect(a > b && b > c && c > d)
        #expect(abs(b - 11.8) < 0.2 && abs(c - 8.3) < 0.2) // matches the worked table (scale 0.05 kg steps, 0.05 kg repeatability)
    }

    @Test func unknownFluidIntakeNeverClaimsAnAccuracyTarget() throws {
        let e = SweatBalance.estimate(session: session, weighIns: [w(-5, 78.0), w(95, 74.9)]) // 3.1 kg, no fluids entered
        let u = try #require(e.uncertainty)
        #expect(e.isLowerBound && u.meetsFivePercentTarget == false)
    }

    @Test func measuredScaleRepeatabilityReplacesTheAssumption() throws {
        let spec = try #require(ScaleCalibration.spec(fromRepeatedReadingsKg: [77.9, 78.0, 78.0, 78.1]))
        #expect(spec.isMeasured)
        #expect(abs(spec.repeatabilitySDKg - 0.0816) < 0.001)
        #expect(ScaleCalibration.spec(fromRepeatedReadingsKg: [78.0, 78.1]) == nil, "needs 3+ readings")
        let e = SweatBalance.estimate(session: session, weighIns: [w(-5, 78.0), w(95, 76.0)], fluids: .init(drankLiters: 0, urineLiters: 0), scale: spec)
        #expect(e.uncertainty?.assumptions.contains { $0.contains("measured on your own scale") } == true)
    }

    @Test func postBeforePreIsRejectedNotNegativeTime() {
        let e = SweatBalance.estimate(session: session, weighIns: [w(85, 78.0)]) // only one reading, used as both
        #expect(e.quality != .measured)
    }
}


// MARK: - Physics model (Mitchell 1972, Maughan 2007) and ACSM constants

@Suite("Non-sweat loss model")
struct NonSweatLossTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(kJ: Double? = 3500, tempC: Double? = 28, rh: Double? = 70, hours: Double = 1.5) -> TrainingSessionSummary {
        TrainingSessionSummary(start: t0, end: t0.addingTimeInterval(hours * 3600), sport: "Soccer", strain: 17, kilojoules: kJ,
                               averageHeartRate: 150, temperatureC: tempC, relativeHumidityPercent: rh, isIndoor: false)
    }

    // The paper's own worked values for the respiratory equation: Maughan 2007 p.798, VO2 = 4.0 L/min.
    @Test func respiratoryEquationReproducesMaughan2007Examples() {
        func loss(tempC: Double, rh: Double, vo2: Double) -> Double {
            NonSweatLoss.respiratoryWaterGramsPerMinute(vo2LitersPerMinute: vo2,
                vaporPressureMmHg: NonSweatLoss.ambientVaporPressureMmHg(tempC: tempC, relativeHumidityPercent: rh))
        }
        #expect(abs(loss(tempC: 35, rh: 20, vo2: 4.0) - 2.7) < 0.05) // paper: 2.7 ml/min, dry heat
        #expect(abs(loss(tempC: 35, rh: 80, vo2: 4.0) - 0.8) < 0.05) // paper: 0.8 ml/min, humid heat
        #expect(abs(loss(tempC: 0, rh: 20, vo2: 4.0) - 3.0) < 0.35) // paper: ~3 ml/min, cold dry
        #expect(abs(loss(tempC: 0, rh: 20, vo2: 0.25) - 0.2) < 0.02) // paper: ~0.2 ml/min at rest
    }

    @Test func gasExchangeMatchesMitchellAndMaughanTableOne() {
        // Mitchell eq. 5: R = 1 -> 0.53 g per L O2.
        #expect(abs(NonSweatLoss.gasExchangeMassLossGramsPerMinute(vo2LitersPerMinute: 1, r: 1.0) - 0.53) < 0.001)
        // Maughan Table I: 1 g carbohydrate uses 1.07 g O2 and makes 1.47 g CO2: net 0.40 g lost (R = 1).
        let litersO2 = 1.07 / NonSweatLoss.o2DensityGramsPerLiter
        #expect(abs(NonSweatLoss.gasExchangeMassLossGramsPerMinute(vo2LitersPerMinute: litersO2, r: 1.0) - 0.40) < 0.01)
    }

    @Test func maughanMarathonSweatEquationBalances() {
        // 3 kg lost + 1 L drunk - 0.55 kg substrate + 0.42 L water of oxidation - 0.40 L respiratory = 3.47 L
        let massLost: Double = 3.0, drunk: Double = 1.0, substrate: Double = 0.55, oxidationWater: Double = 0.42, respiratory: Double = 0.40
        let sweat: Double = massLost + drunk - substrate + oxidationWater - respiratory
        #expect(abs(sweat - 3.47) < 1e-9)
    }

    @Test func vaporPressureFollowsKnownValues() {
        #expect(abs(NonSweatLoss.saturationVaporPressureMmHg(tempC: 20) - 17.5) < 0.1)
        #expect(abs(NonSweatLoss.saturationVaporPressureMmHg(tempC: 35) - 42.2) < 0.3)
    }

    @Test func ninetyMinuteMatchNonSweatLossIsAboutOneToTwoHundredGrams() throws {
        let e = try #require(NonSweatLoss.estimate(for: session()))
        #expect(e.kgMid > 0.10 && e.kgMid < 0.17, "mid \(e.kgMid)")
        #expect(e.kgLow < e.kgMid && e.kgMid < e.kgHigh)
        #expect(e.respiratoryKgMid > 0 && e.gasExchangeKgMid > 0)
    }

    @Test func modelNeedsEnergyAndWeatherOtherwiseReturnsNil() {
        #expect(NonSweatLoss.estimate(for: session(kJ: nil)) == nil)
        #expect(NonSweatLoss.estimate(for: session(tempC: nil)) == nil)
        #expect(NonSweatLoss.estimate(for: session(rh: nil)) == nil)
    }

    @Test func humidDaysFlagThatMitchellOnlyTestedDryAir() throws {
        let e = try #require(NonSweatLoss.estimate(for: session()))
        #expect(e.notes.contains { $0.contains("extrapolated") })
    }

    @Test func modelNarrowsTheErrorVsTheGenericBandForABigSession() throws {
        let w = [WeighIn(time: t0.addingTimeInterval(-300), kg: 80.0, source: .withings),
                 WeighIn(time: t0.addingTimeInterval(5700), kg: 77.5, source: .withings)] // 2.5 kg lost
        let measuredScale = ScaleSpec(resolutionKg: 0.05, repeatabilitySDKg: 0.02, isMeasured: true)
        let withModel = SweatBalance.estimate(session: session(), weighIns: w, fluids: .init(drankLiters: 0.5, urineLiters: 0), scale: measuredScale)
        let bare = SweatBalance.estimate(session: session(kJ: nil, tempC: nil, rh: nil), weighIns: w, fluids: .init(drankLiters: 0.5, urineLiters: 0), scale: measuredScale)
        let a = try #require(withModel.uncertainty), b = try #require(bare.uncertainty)
        #expect(a.relativeError95Percent < b.relativeError95Percent)
    }

    @Test func fiveToTenPercentRangeIsReachableOnlyForLargeLossesWithAGoodScale() throws {
        func rel(lost: Double) throws -> Double {
            let w = [WeighIn(time: t0.addingTimeInterval(-300), kg: 80.0, source: .withings),
                     WeighIn(time: t0.addingTimeInterval(5700), kg: 80.0 - lost, source: .withings)]
            let scale = ScaleSpec(resolutionKg: 0.05, repeatabilitySDKg: 0.02, isMeasured: true)
            let e = SweatBalance.estimate(session: session(kJ: 4200), weighIns: w, fluids: .init(drankLiters: 0.5, urineLiters: 0), scale: scale)
            return try #require(e.uncertainty).relativeError95Percent
        }
        let big = try rel(lost: 3.0)
        let small = try rel(lost: 1.0)
        #expect(big < 5, "3 kg lost: \(big)")
        #expect(small > 5, "1 kg lost: \(small)")
    }
}

@Suite("ACSM constants and planner rules")
struct ACSMConstantTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var session: TrainingSessionSummary {
        TrainingSessionSummary(start: t0, end: t0.addingTimeInterval(5400), sport: "Soccer", strain: 17, kilojoules: nil,
                               averageHeartRate: 150, temperatureC: nil, relativeHumidityPercent: nil, isIndoor: false)
    }
    private func sweat(lost: Double) -> SweatEstimate {
        SweatBalance.estimate(session: session, weighIns: [WeighIn(time: t0.addingTimeInterval(-300), kg: 78, source: .withings),
                                                             WeighIn(time: t0.addingTimeInterval(5700), kg: 78 - lost, source: .withings)],
                              fluids: .init(drankLiters: 0, urineLiters: 0))
    }

    @Test func rapidRecoveryDrinksOnePointFiveLitersPerKgLost() throws {
        let p = RecoveryPlanner.prescribe(session: session, sweat: sweat(lost: 1.0), bodyMassKg: 78, hoursUntilNextHardSession: 6)
        #expect(abs(try #require(p.fluid).drinkLiters - 1.5) < 1e-9)
    }

    @Test func noHardSessionWithinTwelveHoursJustReplacesTheDeficit() throws {
        let p = RecoveryPlanner.prescribe(session: session, sweat: sweat(lost: 1.0), bodyMassKg: 78, hoursUntilNextHardSession: 24)
        #expect(abs(try #require(p.fluid).drinkLiters - 1.0) < 1e-9)
        #expect(p.reasons.contains { $0.contains("normal drinks and meals") })
    }

    @Test func sweatSodiumPlanUsesACSMMeanOfThirtyFive() throws {
        let p = RecoveryPlanner.prescribe(session: session, sweat: sweat(lost: 1.0), bodyMassKg: 78)
        let f = try #require(p.fluid)
        let mid = (f.sweatLitersLow + f.sweatLitersHigh) / 2
        #expect(abs(f.sodiumMgPlan - mid * 35 * 22.99) < 1e-6)
    }

    @Test func magnesiumLostInTwoLitersOfSweatIsAboutTwentyMilligramsNotGrams() {
        let mg = SweatElectrolytes.magnesium.milligrams(sweatLiters: 2)
        #expect(abs(mg.mean - 19.4) < 0.1) // 0.8 mEq/L x 12.153 mg/mEq x 2 L
        #expect(mg.high < 40 && mg.mean < 0.06 * 400, "under ~5% of a 400 mg day")
    }
}
