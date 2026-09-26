import Fluent
import Foundation
import Vapor

// MARK: - WeeklyPlanPipeline

//
// The parse → resolve → solve → rewrite step of the weekly meal-plan job,
// pulled out as a pure(-ish) function so it's unit-testable without a live
// Claude call: it takes the raw AI text directly (already-fetched) and an
// injectable nutrition resolver. WeeklyPlanJob is the only real caller; it
// owns the actual Claude round-trip.

// MARK: - Resolver seam

/// Narrow protocol matching `FoodNutritionResolver.resolve(_:[String],on:)`
/// so tests can inject a fake without a Postgres-backed cache or the real
/// USDA client.
protocol WeeklyPlanFoodResolving: Sendable {
    func resolve(_ names: [String], on req: Request) async -> [String: ResolvedNutrition?]
}

extension FoodNutritionResolver: WeeklyPlanFoodResolving {}

// MARK: - Errors

enum WeeklyPlanPipelineError: Error, CustomStringConvertible, Sendable {
    /// Claude's text couldn't be turned into the expected JSON shape at all
    /// (no `{...}` found, or the JSON didn't decode).
    case unreadable(String)

    var description: String {
        switch self {
        case let .unreadable(reason): "weekly plan AI response unreadable: \(reason)"
        }
    }
}

// MARK: - Pipeline

enum WeeklyPlanPipeline {
    /// Confident-match threshold below which we fall back to the AI's own
    /// per-100g estimate instead of the USDA value. Per spec: 0.6.
    static let defaultConfidenceThreshold = 0.6

    static func build(
        rawAIText: String,
        targetsByDayType: [String: MacroTargets],
        resolver: any WeeklyPlanFoodResolving,
        confidenceThreshold: Double = defaultConfidenceThreshold,
        solver: MacroSolver = MacroSolver(),
        on req: Request
    ) async throws -> WeeklyPlanOutput {
        let jsonString = extractJSON(from: rawAIText)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw WeeklyPlanPipelineError.unreadable("response is not valid UTF-8")
        }

        let aiResponse: AIWeeklyPlanResponse
        do {
            aiResponse = try JSONDecoder().decode(AIWeeklyPlanResponse.self, from: jsonData)
        } catch {
            throw WeeklyPlanPipelineError.unreadable("\(error)")
        }

        // Batch-resolve every non-restaurant food name across the whole
        // week in one call (FoodNutritionResolver dedupes internally too,
        // but deduping here avoids handing it near-duplicate arrays).
        var namesToResolve: Set<String> = []
        for day in aiResponse.days {
            for meal in day.meals {
                for food in meal.foods where (food.source ?? "home") != "restaurant" {
                    namesToResolve.insert(food.name)
                }
            }
        }
        let resolved = namesToResolve.isEmpty
            ? [:]
            : await resolver.resolve(Array(namesToResolve), on: req)

        var outputDays: [OutputDay] = []
        var summaries: [WeeklyPlanSolverSummary] = []

        for day in aiResponse.days {
            var items: [SolverItem] = []
            var perFoodMeta: [String: FoodMeta] = [:]

            for (mealIndex, meal) in day.meals.enumerated() {
                for (foodIndex, food) in meal.foods.enumerated() {
                    let id = "\(mealIndex)-\(foodIndex)"
                    let isRestaurant = (food.source ?? "home") == "restaurant"
                    let grams = max(food.quantityGrams, 0.1)

                    let meta: FoodMeta
                    if isRestaurant {
                        meta = FoodMeta(
                            per100: PerHundred(
                                kcal: food.calories / grams * 100,
                                protein: food.proteinG / grams * 100,
                                carbs: food.carbsG / grams * 100,
                                fat: food.fatG / grams * 100
                            ),
                            source: "restaurant",
                            approx: true,
                            fdcId: nil
                        )
                    } else if let match = resolved[food.name] ?? nil, match.confidence >= confidenceThreshold {
                        meta = FoodMeta(
                            per100: PerHundred(kcal: match.kcal, protein: match.protein, carbs: match.carbs, fat: match.fat),
                            source: "usda",
                            approx: false,
                            fdcId: match.fdcId
                        )
                    } else {
                        meta = FoodMeta(
                            per100: PerHundred(
                                kcal: food.calories / grams * 100,
                                protein: food.proteinG / grams * 100,
                                carbs: food.carbsG / grams * 100,
                                fat: food.fatG / grams * 100
                            ),
                            source: "ai",
                            approx: false,
                            fdcId: nil
                        )
                    }
                    perFoodMeta[id] = meta

                    items.append(SolverItem(
                        id: id,
                        kcalPer100g: meta.per100.kcal,
                        proteinPer100g: meta.per100.protein,
                        carbsPer100g: meta.per100.carbs,
                        fatPer100g: meta.per100.fat,
                        initialGrams: food.quantityGrams,
                        isFixed: isRestaurant
                    ))
                }
            }

            let targets = resolveTargets(dayType: day.dayType, table: targetsByDayType)
            let result = solver.solve(targets: targets, items: items)
            let solvedGrams = Dictionary(uniqueKeysWithValues: result.items.map { ($0.id, $0.grams) })

            var outMeals: [OutputMeal] = []
            for (mealIndex, meal) in day.meals.enumerated() {
                var outFoods: [OutputFood] = []
                for (foodIndex, food) in meal.foods.enumerated() {
                    let id = "\(mealIndex)-\(foodIndex)"
                    guard let meta = perFoodMeta[id], let grams = solvedGrams[id] else { continue }
                    outFoods.append(OutputFood(
                        name: food.name,
                        quantityGrams: grams,
                        calories: Int((meta.per100.kcal * grams / 100).rounded()),
                        proteinG: round1(meta.per100.protein * grams / 100),
                        carbsG: round1(meta.per100.carbs * grams / 100),
                        fatG: round1(meta.per100.fat * grams / 100),
                        source: meta.source,
                        approx: meta.approx,
                        fdcId: meta.fdcId,
                        restaurant: food.restaurant
                    ))
                }
                outMeals.append(OutputMeal(
                    mealNumber: meal.mealNumber,
                    mealName: meal.mealName,
                    scheduledTime: meal.scheduledTime,
                    foods: outFoods
                ))
            }

            outputDays.append(OutputDay(
                dayIndex: day.dayIndex,
                dayType: day.dayType,
                meals: outMeals,
                supplements: day.supplements
            ))
            summaries.append(WeeklyPlanSolverSummary(
                dayIndex: day.dayIndex,
                withinTolerance: result.withinTolerance,
                kcalError: result.error.kcal,
                proteinError: result.error.proteinG,
                carbsError: result.error.carbsG,
                fatError: result.error.fatG
            ))
        }

        return WeeklyPlanOutput(days: outputDays, solver: summaries)
    }

    // MARK: - Helpers

    private struct PerHundred {
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    private struct FoodMeta {
        let per100: PerHundred
        let source: String
        let approx: Bool
        let fdcId: Int?
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// `targets[day.dayType]`, falling back to "strength", then any target
    /// present, then a zeroed target if `targetsByDayType` was empty (should
    /// never happen — the controller validates it's non-empty on create).
    static func resolveTargets(dayType: String, table: [String: MacroTargets]) -> MacroTargets {
        table[dayType] ?? table["strength"] ?? table.values.first
            ?? MacroTargets(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)
    }

    /// Strips ``` / ```json code fences and takes the outermost `{...}`
    /// object, tolerating leading/trailing commentary Claude sometimes adds
    /// despite being told not to.
    static func extractJSON(from text: String) -> String {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if working.hasPrefix("```") {
            if let firstNewline = working.firstIndex(of: "\n") {
                working = String(working[working.index(after: firstNewline)...])
            } else {
                working = String(working.dropFirst(3))
            }
            if working.hasSuffix("```") {
                working = String(working.dropLast(3))
            }
            working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if working.hasPrefix("{") {
            return working
        }
        if let start = working.firstIndex(of: "{"), let end = working.lastIndex(of: "}") {
            return String(working[start ... end])
        }
        return working
    }
}

// MARK: - AI response shape (input)

//
// Numbers may arrive as JSON strings (Claude occasionally quotes them) —
// every numeric field here goes through the lenient decode helpers below.

struct AIWeeklyPlanResponse: Decodable {
    let days: [AIPlanDay]
}

struct AIPlanDay: Decodable {
    let dayIndex: Int
    let dayType: String
    let meals: [AIPlanMeal]
    let supplements: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case dayIndex, dayType, meals, supplements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayIndex = try c.decodeLenientInt(forKey: .dayIndex)
        dayType = try c.decode(String.self, forKey: .dayType)
        meals = try c.decode([AIPlanMeal].self, forKey: .meals)
        supplements = try c.decodeIfPresent(JSONValue.self, forKey: .supplements)
    }
}

struct AIPlanMeal: Decodable {
    let mealNumber: Int
    let mealName: String
    let scheduledTime: String
    let foods: [AIPlanFood]

    private enum CodingKeys: String, CodingKey {
        case mealNumber, mealName, scheduledTime, foods
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mealNumber = try c.decodeLenientInt(forKey: .mealNumber)
        mealName = try c.decode(String.self, forKey: .mealName)
        scheduledTime = try c.decode(String.self, forKey: .scheduledTime)
        foods = try c.decode([AIPlanFood].self, forKey: .foods)
    }
}

struct AIPlanFood: Decodable {
    let name: String
    let quantityGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    /// "home" | "restaurant". Missing/unrecognized is treated as "home".
    let source: String?
    let restaurant: String?

    private enum CodingKeys: String, CodingKey {
        case name, quantityGrams, calories, proteinG, carbsG, fatG, source, restaurant
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        quantityGrams = try c.decodeLenientDouble(forKey: .quantityGrams)
        calories = try c.decodeLenientDouble(forKey: .calories)
        proteinG = try c.decodeLenientDouble(forKey: .proteinG)
        carbsG = try c.decodeLenientDouble(forKey: .carbsG)
        fatG = try c.decodeLenientDouble(forKey: .fatG)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        restaurant = try c.decodeIfPresent(String.self, forKey: .restaurant)
    }
}

// MARK: - Lenient numeric decoding

extension KeyedDecodingContainer {
    /// Decodes a `Double` that may have arrived as a JSON number OR a
    /// quoted numeric string (Claude occasionally emits `"quantityGrams":
    /// "80"`).
    func decodeLenientDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let raw = try? decode(String.self, forKey: key), let value = Double(raw) {
            return value
        }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: self,
            debugDescription: "Expected a number or numeric string for \(key.stringValue)"
        )
    }

    /// Same as `decodeLenientDouble`, truncating to `Int`.
    func decodeLenientInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value)
        }
        if let raw = try? decode(String.self, forKey: key) {
            if let value = Int(raw) {
                return value
            }
            if let value = Double(raw) {
                return Int(value)
            }
        }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: self,
            debugDescription: "Expected an integer or numeric string for \(key.stringValue)"
        )
    }
}

// MARK: - Output shape (stored in plan_json, returned verbatim to iOS)

//
// Plain camelCase, no custom key strategy anywhere in this file's callers —
// see JSONValue's header comment for why.

struct WeeklyPlanOutput: Codable, Equatable, Sendable {
    var days: [OutputDay]
    var solver: [WeeklyPlanSolverSummary]
}

struct OutputDay: Codable, Equatable, Sendable {
    var dayIndex: Int
    var dayType: String
    var meals: [OutputMeal]
    var supplements: JSONValue?
}

struct OutputMeal: Codable, Equatable, Sendable {
    var mealNumber: Int
    var mealName: String
    var scheduledTime: String
    var foods: [OutputFood]
}

struct OutputFood: Codable, Equatable, Sendable {
    var name: String
    var quantityGrams: Double
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    /// "usda" | "ai" | "restaurant"
    var source: String
    var approx: Bool
    var fdcId: Int?
    var restaurant: String?
}

struct WeeklyPlanSolverSummary: Codable, Equatable, Sendable {
    var dayIndex: Int
    var withinTolerance: Bool
    var kcalError: Double
    var proteinError: Double
    var carbsError: Double
    var fatError: Double
}
