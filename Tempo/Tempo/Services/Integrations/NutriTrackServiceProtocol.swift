//
// NutriTrackServiceProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - NutriTrackConnectionState

enum NutriTrackConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - NutriTrackServiceProtocol

protocol NutriTrackServiceProtocol: Sendable {
    var connectionState: NutriTrackConnectionState { get }
    func connect(baseURL: URL, pin: String) async throws
    func disconnect()
    func fetchTodayMeals() async throws -> NutriTrackDayData
    func fetchMacroBalance() async throws -> MacroBalance
    func fetchWeeklyReport() async throws -> NutriTrackWeeklyReport
}

// MARK: - NutriTrackMeal

struct NutriTrackMeal {
    let name: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let time: Date
}

// MARK: - NutriTrackDayData

struct NutriTrackDayData {
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

// MARK: - MacroBalance

struct MacroBalance {
    let proteinPercentage: Double
    let carbsPercentage: Double
    let fatPercentage: Double
}

// MARK: - NutriTrackWeeklyReport

struct NutriTrackWeeklyReport {
    let averageCalories: Double
    let averageProtein: Double
    let adherencePercentage: Double
    let daysLogged: Int
}
