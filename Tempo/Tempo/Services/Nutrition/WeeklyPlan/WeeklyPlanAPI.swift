//
// WeeklyPlanAPI.swift
// Tempo
//
// Wire types for the server-built weekly plan: the phone sends the prompt it
// built (with every local signal) plus per-day-type targets; the server job
// runs Sonnet, checks each food against USDA, solves the grams so every day
// hits its macros, and pushes "plan ready". See tempo-backend
// WeeklyPlanController / WeeklyPlanJob.
//

import Foundation

// MARK: - WeeklyPlanJobRequest

struct WeeklyPlanJobRequest: Encodable, Sendable {
    struct Target: Codable, Sendable, Equatable {
        let kcal: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
    }

    /// yyyy-MM-dd, the Monday the plan starts.
    let weekStart: String
    let system: String
    let prompt: String
    /// Keyed by DayType raw value ("rest", "strength", …).
    let targets: [String: Target]
    let timezone: String
}

// MARK: - WeeklyPlanJobDTO

struct WeeklyPlanJobDTO: Decodable, Sendable, Equatable {
    enum Status: String, Decodable, Sendable {
        case queued
        case running
        case ready
        case failed
    }

    let id: String
    let weekStart: String
    let status: Status
    let error: String?
    let plan: WeeklyPlanPayload?
}

// MARK: - WeeklyPlanPayload

/// The plan exactly as the generator's parser reads it, plus where each
/// food's numbers came from. Also drives the read-only preview.
struct WeeklyPlanPayload: Codable, Sendable, Equatable {
    struct Day: Codable, Sendable, Equatable {
        let dayIndex: Int
        let dayType: String
        let meals: [Meal]
        let supplements: [Supplement]?
    }

    struct Meal: Codable, Sendable, Equatable {
        let mealNumber: Int
        let mealName: String
        let scheduledTime: String
        let foods: [Food]

        var calories: Double {
            foods.reduce(0) { $0 + $1.calories }
        }
    }

    struct Food: Codable, Sendable, Equatable {
        let name: String
        let quantityGrams: Double
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let source: String?
        let restaurant: String?
    }

    struct Supplement: Codable, Sendable, Equatable {
        let name: String
        let take: Bool
        let timing: String?
        let reason: String?
    }

    let days: [Day]

    /// Re-encoded for `MealPlanGeneratorService.finishWeeklyPlan`.
    var jsonString: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

extension APIEndpoint where Response == WeeklyPlanJobDTO {
    static func createWeeklyPlan() -> Self {
        APIEndpoint(path: "/v1/nutrition/weekly-plans", method: .post)
    }

    static func weeklyPlan(id: String) -> Self {
        APIEndpoint(path: "/v1/nutrition/weekly-plans/\(id)")
    }
}

extension APIEndpoint where Response == WeeklyPlanJobDTO? {
    static func latestWeeklyPlan() -> Self {
        APIEndpoint(path: "/v1/nutrition/weekly-plans/latest")
    }
}
