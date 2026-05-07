//
// MockNutriTrackService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

@Observable
final class MockNutriTrackService: NutriTrackServiceProtocol, @unchecked Sendable {
    private(set) var connectionState: NutriTrackConnectionState = .connected

    func connect(baseURL: URL, pin: String) async throws {
        connectionState = .connecting
        try await Task.sleep(for: .milliseconds(300))
        connectionState = .connected
    }

    func disconnect() {
        connectionState = .disconnected
    }

    func fetchTodayMeals() async throws -> NutriTrackDayData {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        return NutriTrackDayData(
            date: today,
            totalCalories: 2100,
            calorieTarget: 2400,
            proteinGrams: 165,
            proteinTarget: 180,
            carbsGrams: 240,
            carbsTarget: 280,
            fatGrams: 72,
            fatTarget: 80,
            mealsLogged: 3,
            mealsPlanned: 4,
            meals: [
                NutriTrackMeal(
                    name: "Breakfast",
                    calories: 650,
                    proteinGrams: 45,
                    carbsGrams: 72,
                    fatGrams: 22,
                    time: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: today) ?? today
                ),
                NutriTrackMeal(
                    name: "Lunch",
                    calories: 780,
                    proteinGrams: 55,
                    carbsGrams: 88,
                    fatGrams: 28,
                    time: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: today) ?? today
                ),
                NutriTrackMeal(
                    name: "Snack",
                    calories: 670,
                    proteinGrams: 65,
                    carbsGrams: 80,
                    fatGrams: 22,
                    time: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: today) ?? today
                ),
            ]
        )
    }

    func fetchMacroBalance() async throws -> MacroBalance {
        MacroBalance(
            proteinPercentage: 31.4,
            carbsPercentage: 45.7,
            fatPercentage: 22.9
        )
    }

    func fetchWeeklyReport() async throws -> NutriTrackWeeklyReport {
        NutriTrackWeeklyReport(
            averageCalories: 2250,
            averageProtein: 172,
            adherencePercentage: 82.0,
            daysLogged: 6
        )
    }
}
