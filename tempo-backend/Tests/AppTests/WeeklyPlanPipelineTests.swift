@testable import App
import Foundation
import Testing
import Vapor

// MARK: - WeeklyPlanPipeline tests

//
// Pure parse -> resolve -> solve -> rewrite tests. No DB, no Redis, no
// network — FakeWeeklyPlanResolver never touches `req.db`/`req.redis`, so a
// bare (unconfigured) Application is enough to build the `Request` the
// pipeline's signature needs.

@Suite("WeeklyPlanPipeline")
struct WeeklyPlanPipelineTests {
    private func withRequest(_ body: (Request) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            let req = Request(application: app, on: app.eventLoopGroup.next())
            try await body(req)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private struct FakeResolver: WeeklyPlanFoodResolving {
        let table: [String: ResolvedNutrition?]
        func resolve(_ names: [String], on _: Request) async -> [String: ResolvedNutrition?] {
            var result: [String: ResolvedNutrition?] = [:]
            for name in names {
                result[name] = table[name] ?? nil
            }
            return result
        }
    }

    private func usda(fdcId: Int, kcal: Double, protein: Double, carbs: Double, fat: Double, confidence: Double = 0.9) -> ResolvedNutrition {
        ResolvedNutrition(fdcId: fdcId, description: "test food", kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: nil, sugars: nil, confidence: confidence)
    }

    private let strengthTargets = MacroTargets(kcal: 2300, proteinG: 150, carbsG: 250, fatG: 70)

    // MARK: - Happy path / tolerance

    @Test func solvedDayIsWithinTolerance() async throws {
        try await withRequest { req in
            // Quantities chosen so the *day* (all 3 foods together, standing in
            // for a full day's eating) already lands close to the 2300kcal /
            // 150p / 250c / 70f target before the solver touches anything —
            // carbs come almost entirely from the rice (28g/100g), which
            // fixes its gram amount near 893g for a 250g carb target; protein
            // is then split between chicken and the rice's own contribution;
            // the remaining fat gap is closed by the olive oil. This keeps
            // the fixture within MacroSolver's 0.5x-1.8x per-item box
            // constraints (it refines, it doesn't perform unbounded scaling).
            let raw = """
            {"days":[{"dayIndex":0,"dayType":"strength","meals":[{"mealNumber":1,"mealName":"Breakfast","scheduledTime":"07:30",
              "foods":[
                {"name":"chicken breast","quantityGrams":406,"calories":670,"proteinG":126,"carbsG":0,"fatG":14.6,"source":"home"},
                {"name":"white rice","quantityGrams":893,"calories":1161,"proteinG":24.1,"carbsG":250,"fatG":2.7,"source":"home"},
                {"name":"olive oil","quantityGrams":53,"calories":469,"proteinG":0,"carbsG":0,"fatG":53,"source":"home"}
              ]}],
              "supplements":[]}]}
            """
            let resolver = FakeResolver(table: [
                "chicken breast": usda(fdcId: 1, kcal: 165, protein: 31, carbs: 0, fat: 3.6),
                "white rice": usda(fdcId: 2, kcal: 130, protein: 2.7, carbs: 28, fat: 0.3),
                "olive oil": usda(fdcId: 3, kcal: 884, protein: 0, carbs: 0, fat: 100),
            ])

            let output = try await WeeklyPlanPipeline.build(
                rawAIText: raw,
                targetsByDayType: ["strength": strengthTargets],
                resolver: resolver,
                on: req
            )

            #expect(output.solver.count == 1)
            let summary = try #require(output.solver.first)
            #expect(summary.dayIndex == 0)
            #expect(summary.withinTolerance, "expected the solver to hit macro targets with 3 flexible foods")

            let day = try #require(output.days.first)
            let foods = day.meals.flatMap(\.foods)
            for food in foods {
                #expect(food.source == "usda")
                #expect(food.fdcId != nil)
                #expect(food.approx == false)
            }
        }
    }

    // MARK: - Restaurant foods

    @Test func restaurantFoodIsFixedAndApproximate() async throws {
        try await withRequest { req in
            let raw = """
            {"days":[{"dayIndex":0,"dayType":"strength","meals":[{"mealNumber":2,"mealName":"Lunch","scheduledTime":"12:30",
              "foods":[
                {"name":"chicken sandwich","quantityGrams":300,"calories":650,"proteinG":35,"carbsG":60,"fatG":28,"source":"restaurant","restaurant":"Panera Bread"}
              ]}],
              "supplements":null}]}
            """
            // A resolver that would (wrongly) match if ever consulted for the restaurant item.
            let resolver = FakeResolver(table: ["chicken sandwich": usda(fdcId: 999, kcal: 1, protein: 1, carbs: 1, fat: 1)])

            let output = try await WeeklyPlanPipeline.build(
                rawAIText: raw,
                targetsByDayType: ["strength": strengthTargets],
                resolver: resolver,
                on: req
            )

            let food = try #require(output.days.first?.meals.first?.foods.first)
            #expect(food.quantityGrams == 300, "restaurant items must never be rescaled by the solver")
            #expect(food.source == "restaurant")
            #expect(food.approx == true)
            #expect(food.fdcId == nil)
            #expect(food.restaurant == "Panera Bread")
        }
    }

    // MARK: - Supplements pass-through

    @Test func supplementsPassThroughVerbatim() async throws {
        try await withRequest { req in
            let raw = """
            {"days":[{"dayIndex":0,"dayType":"strength","meals":[{"mealNumber":1,"mealName":"Breakfast","scheduledTime":"07:30",
              "foods":[{"name":"oats","quantityGrams":80,"calories":300,"proteinG":10,"carbsG":54,"fatG":5,"source":"home"}]}],
              "supplements":[{"name":"creatine","doseGrams":5,"timing":"post-workout"},{"name":"vitamin d","doseGrams":0.0001}]}]}
            """
            let resolver = FakeResolver(table: [:])

            let output = try await WeeklyPlanPipeline.build(
                rawAIText: raw,
                targetsByDayType: ["strength": strengthTargets],
                resolver: resolver,
                on: req
            )

            let supplements = try #require(output.days.first?.supplements)
            guard case let .array(items) = supplements else {
                Issue.record("expected supplements to decode as a JSON array")
                return
            }
            #expect(items.count == 2)
            guard case let .object(first) = items[0] else {
                Issue.record("expected first supplement to be an object")
                return
            }
            #expect(first["name"] == .string("creatine"))
            #expect(first["doseGrams"] == .number(5))
            #expect(first["timing"] == .string("post-workout"))
        }
    }

    // MARK: - String numbers

    @Test func stringNumbersAreAccepted() async throws {
        try await withRequest { req in
            let raw = """
            {"days":[{"dayIndex":"0","dayType":"strength","meals":[{"mealNumber":"1","mealName":"Breakfast","scheduledTime":"07:30",
              "foods":[{"name":"oats","quantityGrams":"80","calories":"300","proteinG":"10","carbsG":"54","fatG":"5","source":"home"}]}],
              "supplements":[]}]}
            """
            let resolver = FakeResolver(table: [:])

            let output = try await WeeklyPlanPipeline.build(
                rawAIText: raw,
                targetsByDayType: ["strength": strengthTargets],
                resolver: resolver,
                on: req
            )

            let day = try #require(output.days.first)
            #expect(day.dayIndex == 0)
            let food = try #require(day.meals.first?.foods.first)
            #expect(food.quantityGrams > 0)
        }
    }

    // MARK: - Fenced JSON

    @Test func fencedJSONIsAccepted() async throws {
        try await withRequest { req in
            let raw = """
            Here is the plan:
            ```json
            {"days":[{"dayIndex":0,"dayType":"strength","meals":[{"mealNumber":1,"mealName":"Breakfast","scheduledTime":"07:30",
              "foods":[{"name":"oats","quantityGrams":80,"calories":300,"proteinG":10,"carbsG":54,"fatG":5,"source":"home"}]}],
              "supplements":[]}]}
            ```
            """
            let resolver = FakeResolver(table: [:])

            let output = try await WeeklyPlanPipeline.build(
                rawAIText: raw,
                targetsByDayType: ["strength": strengthTargets],
                resolver: resolver,
                on: req
            )
            #expect(output.days.count == 1)
        }
    }

    // MARK: - Unreadable

    @Test func unreadableTextThrows() async throws {
        try await withRequest { req in
            let raw = "Sorry, I can't produce that plan right now."
            let resolver = FakeResolver(table: [:])

            await #expect(throws: WeeklyPlanPipelineError.self) {
                _ = try await WeeklyPlanPipeline.build(
                    rawAIText: raw,
                    targetsByDayType: ["strength": strengthTargets],
                    resolver: resolver,
                    on: req
                )
            }
        }
    }

    @Test func fallsBackToAIValuesWhenResolverHasNoConfidentMatch() async throws {
        try await withRequest { req in
            let raw = """
            {"days":[{"dayIndex":0,"dayType":"strength","meals":[{"mealNumber":1,"mealName":"Breakfast","scheduledTime":"07:30",
              "foods":[{"name":"mystery smoothie","quantityGrams":250,"calories":300,"proteinG":20,"carbsG":40,"fatG":5,"source":"home"}]}],
              "supplements":[]}]}
            """
            // Low-confidence match must be rejected in favor of the AI's own numbers.
            let resolver = FakeResolver(table: ["mystery smoothie": usda(fdcId: 42, kcal: 999, protein: 999, carbs: 999, fat: 999, confidence: 0.2)])

            let output = try await WeeklyPlanPipeline.build(
                rawAIText: raw,
                targetsByDayType: ["strength": strengthTargets],
                resolver: resolver,
                on: req
            )

            let food = try #require(output.days.first?.meals.first?.foods.first)
            #expect(food.source == "ai")
            #expect(food.fdcId == nil)
        }
    }
}
