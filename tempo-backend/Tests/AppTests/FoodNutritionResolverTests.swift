@testable import App
import Fluent
import Foundation
import Testing
import Vapor

// MARK: - FoodNutritionResolver match-selection tests (pure, no Request/DB)

@Suite("FoodNutritionResolver match selection")
struct FoodNutritionResolverMatchTests {
    private func usdaFood(fdcId: Int, description: String, dataType: String? = "Foundation", nutrients: [(Int, Double)]) -> USDASearchRawResponse.Food {
        USDASearchRawResponse.Food(
            fdcId: fdcId, description: description, dataType: dataType, brandOwner: nil, brandName: nil,
            gtinUpc: nil, servingSize: nil, servingSizeUnit: nil,
            foodNutrients: nutrients.map { USDASearchRawResponse.Nutrient(nutrientId: $0.0, value: $0.1) }
        )
    }

    @Test func picksBestOverlapMatchOverAnUnrelatedResult() throws {
        let unrelated = usdaFood(
            fdcId: 1, description: "Soup, chicken noodle, canned, condensed",
            nutrients: [(1008, 60), (1003, 3), (1005, 8), (1004, 1.5)]
        )
        let onTarget = usdaFood(
            fdcId: 2, description: "Chicken, broiler or fryers, breast, meat only, raw",
            nutrients: [(1008, 120), (1003, 22.5), (1005, 0), (1004, 2.6)]
        )
        let result = try #require(FoodNutritionResolver.bestMatch(for: "chicken breast", in: [unrelated, onTarget], threshold: 0.55))
        #expect(result.fdcId == 2)
    }

    @Test func prefersCookedResultWhenQuerySaysGrilled() throws {
        let raw = usdaFood(fdcId: 1, description: "Chicken breast, raw", nutrients: [(1008, 120), (1003, 22.5), (1005, 0), (1004, 2.6)])
        let cooked = usdaFood(fdcId: 2, description: "Chicken breast, cooked, grilled", nutrients: [(1008, 165), (1003, 31), (1005, 0), (1004, 3.6)])
        let result = try #require(FoodNutritionResolver.bestMatch(for: "chicken breast, grilled", in: [raw, cooked], threshold: 0.55))
        #expect(result.fdcId == 2)
    }

    @Test func prefersRawResultWhenQuerySaysRaw() throws {
        let raw = usdaFood(fdcId: 1, description: "Chicken breast, raw", nutrients: [(1008, 120), (1003, 22.5), (1005, 0), (1004, 2.6)])
        let cooked = usdaFood(fdcId: 2, description: "Chicken breast, cooked, grilled", nutrients: [(1008, 165), (1003, 31), (1005, 0), (1004, 3.6)])
        let result = try #require(FoodNutritionResolver.bestMatch(for: "chicken breast, raw", in: [raw, cooked], threshold: 0.55))
        #expect(result.fdcId == 1)
    }

    @Test func rejectsMatchBelowThreshold() {
        let unrelated = usdaFood(fdcId: 1, description: "Beverages, coffee, brewed", nutrients: [(1008, 1), (1003, 0.1), (1005, 0), (1004, 0)])
        let result = FoodNutritionResolver.bestMatch(for: "chicken breast, grilled", in: [unrelated], threshold: 0.55)
        #expect(result == nil)
    }

    @Test func noCandidatesReturnsNilNotCrash() {
        #expect(FoodNutritionResolver.bestMatch(for: "chicken breast", in: [], threshold: 0.55) == nil)
    }

    @Test func candidateMissingCoreMacrosIsSkipped() throws {
        // No energy/macro nutrients at all — FoodDTO(usda:) returns nil for it.
        let noMacros = usdaFood(fdcId: 1, description: "chicken breast grilled", nutrients: [(1258, 0.7)])
        let good = usdaFood(fdcId: 2, description: "chicken breast grilled", nutrients: [(1008, 165), (1003, 31), (1005, 0), (1004, 3.6)])
        let result = try #require(FoodNutritionResolver.bestMatch(for: "chicken breast grilled", in: [noMacros, good], threshold: 0.55))
        #expect(result.fdcId == 2)
    }

    @Test func atwaterInconsistentEnergyLowersConfidence() throws {
        // Reported kcal (400) is far from 4/4/9 (protein 30 + carbs 0 + fat 0 -> 120).
        let inconsistent = usdaFood(fdcId: 1, description: "chicken breast grilled", nutrients: [(1008, 400), (1003, 30), (1005, 0), (1004, 0)])
        let consistent = usdaFood(fdcId: 2, description: "chicken breast grilled", nutrients: [(1008, 141), (1003, 31), (1005, 0), (1004, 3.6)])

        let inconsistentResult = try #require(FoodNutritionResolver.bestMatch(for: "chicken breast grilled", in: [inconsistent], threshold: 0.3))
        let consistentResult = try #require(FoodNutritionResolver.bestMatch(for: "chicken breast grilled", in: [consistent], threshold: 0.3))

        #expect(inconsistentResult.confidence < consistentResult.confidence)
    }

    @Test func atwaterConsistencyHelperMatchesFourFourNineRule() {
        let (consistent, atwaterKcal) = FoodNutritionResolver.atwaterConsistency(kcal: 165, protein: 31, carbs: 0, fat: 3.6)
        let expectedAtwaterKcal = 31.0 * 4.0 + 0.0 * 4.0 + 3.6 * 9.0
        #expect(atwaterKcal == expectedAtwaterKcal)
        #expect(consistent)

        let (inconsistent, _) = FoodNutritionResolver.atwaterConsistency(kcal: 500, protein: 31, carbs: 0, fat: 3.6)
        #expect(!inconsistent)
    }

    @Test func normalizeQueryLowercasesStripsPunctuationAndCollapsesWhitespace() {
        #expect(FoodNutritionResolver.normalizeQuery("Chicken Breast, Grilled!") == "chicken breast grilled")
        #expect(FoodNutritionResolver.normalizeQuery("  Basmati   Rice (cooked)  ") == "basmati rice cooked")
    }
}

// MARK: - FoodNutritionResolver cache tests (real Postgres + Redis)

//
// Same docker-compose-backed harness as ExerciseImageServiceIntegrationTests
// / TrainerProgramImportQuotaServiceTests. Every test injects
// FakeUSDAFoodClient, never USDAAPIClient — this suite must never hit the
// real USDA API. Each test uses a UUID-suffixed food name so cache rows
// never collide across runs against the same persistent database.

@Suite("FoodNutritionResolver cache", .serialized)
struct FoodNutritionResolverCacheTests {
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

    private func uniqueName(_ label: String) -> String {
        "\(label) \(UUID().uuidString.prefix(8))"
    }

    private func coreMacroFood(fdcId: Int, description: String, dataType: String = "Foundation") -> USDASearchRawResponse.Food {
        USDASearchRawResponse.Food(
            fdcId: fdcId, description: description, dataType: dataType, brandOwner: nil, brandName: nil,
            gtinUpc: nil, servingSize: nil, servingSizeUnit: nil,
            foodNutrients: [
                USDASearchRawResponse.Nutrient(nutrientId: 1008, value: 165),
                USDASearchRawResponse.Nutrient(nutrientId: 1003, value: 31),
                USDASearchRawResponse.Nutrient(nutrientId: 1005, value: 0),
                USDASearchRawResponse.Nutrient(nutrientId: 1004, value: 3.6),
            ]
        )
    }

    @Test func cacheHitAvoidsSecondUSDACall() async throws {
        try await withApp { _, req in
            let name = uniqueName("Grilled Chicken Breast")
            let client = FakeUSDAFoodClient(responses: [
                name: .success(USDASearchRawResponse(foods: [coreMacroFood(fdcId: 100, description: name)])),
            ])
            let resolver = FoodNutritionResolver(usdaClient: client)

            let first = try await resolver.resolve(name, on: req)
            #expect(first?.fdcId == 100)
            #expect(client.callCount == 1)

            let second = try await resolver.resolve(name, on: req)
            #expect(second?.fdcId == 100)
            #expect(client.callCount == 1, "a cache hit must not call USDA again")
        }
    }

    @Test func cacheMissIsCachedAndAvoidsSecondUSDACall() async throws {
        try await withApp { _, req in
            let name = uniqueName("Completely Made Up Nonexistent Food Xyzzy")
            let client = FakeUSDAFoodClient(responses: [name: .success(USDASearchRawResponse(foods: []))])
            let resolver = FoodNutritionResolver(usdaClient: client)

            let first = try await resolver.resolve(name, on: req)
            #expect(first == nil)
            #expect(client.callCount == 1)

            let second = try await resolver.resolve(name, on: req)
            #expect(second == nil)
            #expect(client.callCount == 1, "a cached miss must not call USDA again")

            let row = try await CachedFoodNutrition.query(on: req.db)
                .filter(\.$normalizedQuery == FoodNutritionResolver.normalizeQuery(name))
                .first()
            #expect(row?.isHit == false)
            #expect(row?.expiresAt ?? .distantPast < Date().addingTimeInterval(8 * 24 * 3600))
        }
    }

    @Test func usdaTransportErrorPropagatesAndIsNotCachedAsAMiss() async throws {
        try await withApp { _, req in
            struct DummyTransportError: Error {}
            let name = uniqueName("Transient Error Food")
            let client = FakeUSDAFoodClient(responses: [name: .failure(DummyTransportError())])
            let resolver = FoodNutritionResolver(usdaClient: client)

            await #expect(throws: DummyTransportError.self) {
                try await resolver.resolve(name, on: req)
            }

            let row = try await CachedFoodNutrition.query(on: req.db)
                .filter(\.$normalizedQuery == FoodNutritionResolver.normalizeQuery(name))
                .first()
            #expect(row == nil, "a transient USDA error must never be cached as a 7-day miss")

            // A retry after the transient failure resolves normally.
            client.setResponse(.success(USDASearchRawResponse(foods: [coreMacroFood(fdcId: 555, description: name)])), for: name)
            let retried = try await resolver.resolve(name, on: req)
            #expect(retried?.fdcId == 555)
        }
    }

    @Test func concurrentResolvesForTheSameNameDoNotRaceTheUniqueConstraint() async throws {
        try await withApp { _, req in
            let name = uniqueName("Concurrent Race Food")
            let client = FakeUSDAFoodClient(responses: [
                name: .success(USDASearchRawResponse(foods: [coreMacroFood(fdcId: 777, description: name)])),
            ])
            let resolver = FoodNutritionResolver(usdaClient: client)

            // Several concurrent resolves for the same never-before-seen name
            // all race the same INSERT ... ON CONFLICT upsert.
            try await withThrowingTaskGroup(of: ResolvedNutrition?.self) { group in
                for _ in 0 ..< 5 {
                    group.addTask { try await resolver.resolve(name, on: req) }
                }
                for try await result in group {
                    #expect(result?.fdcId == 777)
                }
            }

            let rows = try await CachedFoodNutrition.query(on: req.db)
                .filter(\.$normalizedQuery == FoodNutritionResolver.normalizeQuery(name))
                .all()
            #expect(rows.count == 1, "the unique constraint must collapse concurrent upserts into one row")
        }
    }

    @Test func batchResolveDedupesAndResolvesEveryName() async throws {
        try await withApp { _, req in
            let nameA = uniqueName("Batch Chicken Breast")
            let nameB = uniqueName("Batch Rice Cooked")
            let foodA = coreMacroFood(fdcId: 201, description: nameA)
            let foodB = USDASearchRawResponse.Food(
                fdcId: 202, description: nameB, dataType: "SR Legacy", brandOwner: nil, brandName: nil,
                gtinUpc: nil, servingSize: nil, servingSizeUnit: nil,
                foodNutrients: [
                    USDASearchRawResponse.Nutrient(nutrientId: 1008, value: 130),
                    USDASearchRawResponse.Nutrient(nutrientId: 1003, value: 2.7),
                    USDASearchRawResponse.Nutrient(nutrientId: 1005, value: 28),
                    USDASearchRawResponse.Nutrient(nutrientId: 1004, value: 0.3),
                ]
            )
            let client = FakeUSDAFoodClient(responses: [
                nameA: .success(USDASearchRawResponse(foods: [foodA])),
                nameB: .success(USDASearchRawResponse(foods: [foodB])),
            ])
            let resolver = FoodNutritionResolver(usdaClient: client)

            let results = await resolver.resolve([nameA, nameB, nameA], on: req)
            #expect(results.count == 2)

            let resolvedA = try #require(results[nameA] ?? nil)
            #expect(resolvedA.fdcId == 201)
            let resolvedB = try #require(results[nameB] ?? nil)
            #expect(resolvedB.fdcId == 202)

            // nameA appears twice in the input but is deduplicated before
            // dispatch, so only 2 USDA calls total (one per unique name).
            #expect(client.callCount == 2)
        }
    }

    @Test func batchResolveHandlesAMixOfHitsAndMisses() async throws {
        try await withApp { _, req in
            let found = uniqueName("Batch Found Food")
            let notFound = uniqueName("Batch Unfindable Food")
            let client = FakeUSDAFoodClient(responses: [
                found: .success(USDASearchRawResponse(foods: [coreMacroFood(fdcId: 301, description: found)])),
                notFound: .success(USDASearchRawResponse(foods: [])),
            ])
            let resolver = FoodNutritionResolver(usdaClient: client)

            let results = await resolver.resolve([found, notFound], on: req)
            #expect((results[found] ?? nil)?.fdcId == 301)
            #expect((results[notFound] ?? nil) == nil)
        }
    }
}
