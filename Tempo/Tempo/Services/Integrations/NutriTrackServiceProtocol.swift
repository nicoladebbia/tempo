import Foundation

// MARK: - Connection State

enum NutriTrackConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Protocol

protocol NutriTrackServiceProtocol: Sendable {
    var connectionState: NutriTrackConnectionState { get }
    func connect(baseURL: URL, pin: String) async throws
    func disconnect()
    func fetchTodayMeals() async throws -> NutriTrackDayData
    func fetchMacroBalance() async throws -> MacroBalance
    func fetchWeeklyReport() async throws -> NutriTrackWeeklyReport
}

// MARK: - Data Types

struct NutriTrackMeal: Sendable {
    let name: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let time: Date
}

struct NutriTrackDayData: Sendable {
    let date: Date
    let totalCalories: Double
    let calorieTarget: Double
    let proteinGrams: Double
    let proteinTarget: Double
    let carbsGrams: Double
    let carbsTarget: Double
    let fatGrams: Double
    let fatTarget: Double
    let mealsLogged: Int
    let mealsPlanned: Int
    let meals: [NutriTrackMeal]
}

struct MacroBalance: Sendable {
    let proteinPercentage: Double
    let carbsPercentage: Double
    let fatPercentage: Double
}

struct NutriTrackWeeklyReport: Sendable {
    let averageCalories: Double
    let averageProtein: Double
    let adherencePercentage: Double
    let daysLogged: Int
}
