@testable import App
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor

// MARK: - Catalog

@Suite("Nutrient catalog")
struct NutrientCatalogTests {
    @Test func usdaIdsAreUnique() {
        let ids = Nutrient.allCases.map(\.usdaId)
        #expect(Set(ids).count == ids.count)
        #expect(Nutrient.byUSDAId.count == Nutrient.allCases.count)
    }

    @Test func idsMatchTheLiveUSDAResponseWeVerified() {
        // Verified against api.nal.usda.gov foods/search on 2026-11-20.
        #expect(Nutrient.vitaminD.usdaId == 1114 && Nutrient.vitaminD.unit == .mcg)
        #expect(Nutrient.magnesium.usdaId == 1090 && Nutrient.magnesium.unit == .mg)
        #expect(Nutrient.vitaminB12.usdaId == 1178 && Nutrient.vitaminB12.unit == .mcg)
        #expect(Nutrient.dha.usdaId == 1272 && Nutrient.epa.usdaId == 1278)
        #expect(Nutrient.folate.usdaId == 1190)
    }

    @Test func unitsMatchWhatUSDAReports() {
        // Pinned from a live foods/search response (2026-11-20). Copper is MG, not µg.
        let usda: [Nutrient: Nutrient.Unit] = [
            .vitaminA: .mcg, .vitaminC: .mg, .vitaminD: .mcg, .vitaminE: .mg, .vitaminK: .mcg,
            .thiamin: .mg, .riboflavin: .mg, .niacin: .mg, .pantothenicAcid: .mg, .vitaminB6: .mg,
            .folate: .mcg, .vitaminB12: .mcg, .choline: .mg, .calcium: .mg, .iron: .mg, .magnesium: .mg,
            .phosphorus: .mg, .potassium: .mg, .sodium: .mg, .zinc: .mg, .copper: .mg, .manganese: .mg,
            .selenium: .mcg, .omega3ALA: .g, .epa: .g, .dha: .g, .saturatedFat: .g, .cholesterol: .mg, .fiber: .g,
        ]
        #expect(Set(usda.keys) == Set(Nutrient.allCases))
        for (nutrient, unit) in usda { #expect(nutrient.unit == unit, "\(nutrient)") }
    }

    @Test func extractorKeepsOnlyCataloguedNutrientsAndClampsNegatives() {
        let food = USDASearchRawResponse.Food(
            fdcId: 1, description: "salmon", dataType: "SR Legacy", brandOwner: nil, brandName: nil,
            gtinUpc: nil, servingSize: nil, servingSizeUnit: nil,
            foodNutrients: [
                .init(nutrientId: 1114, value: 11.0), // vitamin D
                .init(nutrientId: 1090, value: 27.0), // magnesium
                .init(nutrientId: 1003, value: 20.4), // protein: not a micro, ignored
                .init(nutrientId: 1092, value: -0.2), // negative artefact
                .init(nutrientId: 1087, value: nil), // no value
            ]
        )
        let micros = MicronutrientExtractor.extract(from: food)
        #expect(micros == ["vitaminD": 11.0, "magnesium": 27.0, "potassium": 0.0])
    }
}

// MARK: - Targets

@Suite("Nutrient targets")
struct NutrientTargetsTests {
    private func amount(_ n: Nutrient, _ profile: NutritionProfile) -> Double? {
        NutrientTargets.target(for: n, profile: profile)?.amount
    }

    @Test func underNineteenAndPregnancyAreNotGuessed() {
        #expect(NutrientTargets.targets(for: .init(sex: .male, ageYears: 18)) == nil)
        #expect(NutrientTargets.targets(for: .init(sex: .female, ageYears: 28, isPregnantOrLactating: true)) == nil)
    }

    @Test func ironDiffersByAndSexAndAge() {
        #expect(amount(.iron, .init(sex: .male, ageYears: 25)) == 8)
        #expect(amount(.iron, .init(sex: .female, ageYears: 25)) == 18)
        #expect(amount(.iron, .init(sex: .female, ageYears: 55)) == 8)
    }

    @Test func magnesiumAndVitaminDFollowAgeBands() {
        #expect(amount(.magnesium, .init(sex: .male, ageYears: 22)) == 400)
        #expect(amount(.magnesium, .init(sex: .male, ageYears: 40)) == 420)
        #expect(amount(.vitaminD, .init(sex: .male, ageYears: 40)) == 15)
        #expect(amount(.vitaminD, .init(sex: .male, ageYears: 75)) == 20)
    }

    @Test func everyCataloguedNutrientExceptTheCholesterolAndSatFatHasATarget() throws {
        let targets = try #require(NutrientTargets.targets(for: .init(sex: .male, ageYears: 25)))
        let covered = Set(targets.map(\.nutrient))
        #expect(Set(Nutrient.allCases).subtracting(covered) == [.saturatedFat, .cholesterol])
    }

    @Test func supplementOnlyLimitsAreMarkedSoFoodAloneNeverTripsThem() throws {
        let mg = try #require(NutrientTargets.target(for: .magnesium, profile: .init(sex: .male, ageYears: 25)))
        #expect(mg.upperLimit == 350 && mg.ulScope == .supplementsOnly)
        let d = try #require(NutrientTargets.target(for: .vitaminD, profile: .init(sex: .male, ageYears: 25)))
        #expect(d.upperLimit == 100 && d.ulScope == .total)
    }
}

// MARK: - Gap detector

@Suite("Gap detector")
struct GapDetectorTests {
    private let profile = NutritionProfile(sex: .male, ageYears: 21)
    private let detector = GapDetector()

    /// A day that meets every target, so a test changes only what it is about.
    private func fullDay(_ date: String, kcal: Double = 2800, protein: Double = 150, overrides: [Nutrient: Double] = [:]) -> DailyIntake {
        var nutrients: [Nutrient: Double] = [:]
        for t in NutrientTargets.targets(for: profile)! where t.kind != .limit { nutrients[t.nutrient] = t.amount * 1.1 }
        for (k, v) in overrides { nutrients[k] = v }
        return DailyIntake(date: date, kcal: kcal, proteinGrams: protein, nutrients: nutrients)
    }

    private func week(_ make: (Int) -> DailyIntake) -> [DailyIntake] { (1 ... 7).map(make) }

    @Test func fewerThanThreeWellLoggedDaysIsInsufficientNotDeficient() {
        let days = [fullDay("d1"), fullDay("d2")]
        let result = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150)
        #expect(result.status == .insufficientData(completeDays: 2))
        #expect(result.gaps.isEmpty)
    }

    @Test func halfLoggedDaysAreIgnoredSoTheyCannotFakeAGap() {
        var days = week { fullDay("d\($0)") }
        days.append(DailyIntake(date: "half", kcal: 900, proteinGrams: 20, nutrients: [:]))
        let result = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150)
        #expect(result.completeDays == 7)
        #expect(result.gaps.isEmpty)
    }

    @Test func findsTheRealProteinShortfall() throws {
        let days = week { fullDay("d\($0)", protein: 130) } // 20 g short
        let result = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150)
        let gap = try #require(result.gaps.first { $0.subject == .protein })
        #expect(abs(gap.shortfallPerDay - 20) < 0.001)
        #expect(gap.severity == .mild) // 130/150 = 87%
    }

    @Test func severityBandsFollowPercentOfTarget() throws {
        func severity(of intake: Double) throws -> NutritionGap.Severity {
            let days = week { fullDay("d\($0)", overrides: [.zinc: intake]) } // target 11 mg
            let r = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150)
            return try #require(r.gaps.first { $0.subject == .nutrient(.zinc) }).severity
        }
        #expect(try severity(of: 5) == .high) // 45%
        #expect(try severity(of: 7) == .moderate) // 64%
        #expect(try severity(of: 9) == .mild) // 82%
    }

    @Test func noGapAtNinetyPercentOrAbove() {
        let days = week { fullDay("d\($0)", overrides: [.zinc: 10]) } // 91%
        let r = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150)
        #expect(r.gaps.contains { $0.subject == .nutrient(.zinc) } == false)
    }

    @Test func lowSunExplainsAndEscalatesVitaminD() throws {
        let days = week { fullDay("d\($0)", overrides: [.vitaminD: 8]) } // 53% of 15 µg -> moderate
        let sunny = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150,
                                     context: .init(avgDaylightMinutes: 60))
        let indoors = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150,
                                       context: .init(avgDaylightMinutes: 6))
        let sunnyGap = try #require(sunny.gaps.first { $0.subject == .nutrient(.vitaminD) })
        let indoorGap = try #require(indoors.gaps.first { $0.subject == .nutrient(.vitaminD) })
        #expect(sunnyGap.severity == .moderate && sunnyGap.reasons.isEmpty)
        #expect(indoorGap.severity == .high)
        #expect(indoorGap.reasons.first?.contains("6 min") == true)
    }

    @Test func winterAtHighLatitudeCountsAsLowSunOnlyInTheRightHemisphere() {
        #expect(GapDetector.isLowSun(.init(latitude: 45, month: 1)))
        #expect(!GapDetector.isLowSun(.init(latitude: 45, month: 7)))
        #expect(GapDetector.isLowSun(.init(latitude: -40, month: 7)))
        #expect(!GapDetector.isLowSun(.init(latitude: 25.8, month: 1))) // 25.8 N
        #expect(!GapDetector.isLowSun(.init())) // no signal, no claim
    }

    @Test func totalULBreachIsReportedButSupplementOnlyULIsNot() {
        let days = week { fullDay("d\($0)", overrides: [.vitaminD: 120, .magnesium: 500, .sodium: 3000]) }
        let r = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150)
        let over = Dictionary(uniqueKeysWithValues: r.overages.map { ($0.nutrient, $0) })
        #expect(over[.vitaminD]?.isUpperLimit == true)
        #expect(over[.sodium]?.isUpperLimit == false)
        #expect(over[.magnesium] == nil, "magnesium UL is supplement-only; food can't breach it")
    }

    @Test func rankingPutsWorseAndMoreImportantGapsFirst() {
        let days = week { fullDay("d\($0)", protein: 130, overrides: [.vitaminD: 3, .copper: 0.4]) }
        let r = detector.analyze(profile: profile, days: days, calorieTarget: 2800, proteinTargetGrams: 150)
        // vitamin D 20% and copper 44% are both .high; vitamin D is worse and higher priority.
        #expect(r.gaps.first?.subject == .nutrient(.vitaminD))
        let order = r.gaps.map(\.subject)
        #expect(order.firstIndex(of: .nutrient(.vitaminD))! < order.firstIndex(of: .nutrient(.copper))!)
        #expect(order.firstIndex(of: .nutrient(.copper))! < order.firstIndex(of: .protein)!)
    }

    @Test func unsupportedProfileReturnsNoNumbers() {
        let r = detector.analyze(profile: .init(sex: .female, ageYears: 16), days: [fullDay("d1")], calorieTarget: 2000, proteinTargetGrams: 100)
        #expect(r.status == .unsupportedProfile)
        #expect(r.gaps.isEmpty)
    }
}

// MARK: - Resolver micros through the cache

@Suite("Resolver micronutrients", .serialized)
struct ResolverMicronutrientTests {
    private func withApp(_ body: (Application, Request) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            let req = Request(application: app, on: app.eventLoopGroup.next())
            try await body(app, req)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func salmon(_ name: String) -> USDASearchRawResponse.Food {
        USDASearchRawResponse.Food(
            fdcId: 175_167, description: name, dataType: "SR Legacy", brandOwner: nil, brandName: nil,
            gtinUpc: nil, servingSize: nil, servingSizeUnit: nil,
            foodNutrients: [
                .init(nutrientId: 1008, value: 208), .init(nutrientId: 1003, value: 20.4),
                .init(nutrientId: 1005, value: 0), .init(nutrientId: 1004, value: 13.4),
                .init(nutrientId: 1114, value: 11.0), .init(nutrientId: 1090, value: 27.0),
            ]
        )
    }

    private func legacyRow(_ name: String) async throws -> (Request) async throws -> Void {
        { req in
            let legacy = CachedFoodNutrition(
                normalizedQuery: FoodNutritionResolver.normalizeQuery(name),
                resolved: ResolvedNutrition(fdcId: 1, description: "old", kcal: 208, protein: 20.4, carbs: 0, fat: 13.4, fiber: nil, sugars: nil, micros: nil, confidence: 0.9),
                expiresAt: Date().addingTimeInterval(3600)
            )
            try await legacy.create(on: req.db)
        }
    }

    @Test func legacyRowSurvivesAUSDAErrorDuringRefresh() async throws {
        try await withApp { _, req in
            let name = "Salmon legacy err \(UUID().uuidString.prefix(8))"
            try await legacyRow(name)(req)
            let client = FakeUSDAFoodClient(responses: [name: .failure(Abort(.tooManyRequests))])
            let result = try await FoodNutritionResolver(usdaClient: client).resolve(name, on: req)
            #expect(result?.fdcId == 1 && result?.protein == 20.4, "good cached macros must still be served")
        }
    }

    @Test func legacyRowSurvivesAUSDAMissAndStopsRefreshing() async throws {
        try await withApp { _, req in
            let name = "Salmon legacy miss \(UUID().uuidString.prefix(8))"
            try await legacyRow(name)(req)
            let client = FakeUSDAFoodClient(responses: [name: .success(USDASearchRawResponse(foods: []))])
            let resolver = FoodNutritionResolver(usdaClient: client)
            let first = try await resolver.resolve(name, on: req)
            #expect(first?.protein == 20.4, "macros kept, not replaced by a miss")
            _ = try await resolver.resolve(name, on: req)
            #expect(client.callCount == 1, "no endless refresh")
        }
    }

    @Test func microsSurviveTheCacheRoundTrip() async throws {
        try await withApp { _, req in
            let name = "Salmon Atlantic raw \(UUID().uuidString.prefix(8))"
            let client = FakeUSDAFoodClient(responses: [name: .success(USDASearchRawResponse(foods: [salmon(name)]))])
            let resolver = FoodNutritionResolver(usdaClient: client)

            let first = try await resolver.resolve(name, on: req)
            #expect(first?.micros?["vitaminD"] == 11.0)

            let second = try await resolver.resolve(name, on: req)
            #expect(client.callCount == 1, "second lookup must come from cache")
            #expect(second?.micros == ["vitaminD": 11.0, "magnesium": 27.0])
        }
    }

    @Test func rowCachedBeforeMicrosExistedIsRefreshedOnce() async throws {
        try await withApp { _, req in
            let name = "Salmon legacy row \(UUID().uuidString.prefix(8))"
            let normalized = FoodNutritionResolver.normalizeQuery(name)
            // A pre-migration hit: all macros present, micros NULL.
            let legacy = CachedFoodNutrition(
                normalizedQuery: normalized,
                resolved: ResolvedNutrition(fdcId: 1, description: "old", kcal: 208, protein: 20.4, carbs: 0, fat: 13.4, fiber: nil, sugars: nil, micros: nil, confidence: 0.9),
                expiresAt: Date().addingTimeInterval(3600)
            )
            try await legacy.create(on: req.db)

            let client = FakeUSDAFoodClient(responses: [name: .success(USDASearchRawResponse(foods: [salmon(name)]))])
            let resolver = FoodNutritionResolver(usdaClient: client)

            let healed = try await resolver.resolve(name, on: req)
            #expect(client.callCount == 1, "legacy row must trigger one refetch")
            #expect(healed?.micros?["magnesium"] == 27.0)

            _ = try await resolver.resolve(name, on: req)
            #expect(client.callCount == 1, "after healing it is a normal cache hit")
        }
    }
}
