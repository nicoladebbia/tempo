//
// MealLoggingService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import os
import SwiftData

// MARK: - MealLoggingServiceProtocol

protocol MealLoggingServiceProtocol: Sendable {
    func logMeal(type: MealType, items: [MealFoodItemInput], photo: Data?, source: MealSource, context: ModelContext) async throws
        -> MealLog
    func updateMeal(_ meal: MealLog, items: [MealFoodItemInput], context: ModelContext) throws
    func deleteMeal(_ meal: MealLog, context: ModelContext) throws
    func fetchTodayMeals(context: ModelContext) -> [MealLog]
    func fetchMeals(for date: Date, context: ModelContext) -> [MealLog]
    func todaySummary(context: ModelContext) -> DailyNutritionSummary
    func syncToHealthKit(_ meal: MealLog) async throws
}

// MARK: - MealLoggingService

@Observable
final class MealLoggingService: MealLoggingServiceProtocol, @unchecked Sendable {
    private let healthKit: any HealthKitServiceProtocol
    private let logger = Logger.nutrition

    init(healthKit: any HealthKitServiceProtocol) {
        self.healthKit = healthKit
    }

    // MARK: - Log Meal

    func logMeal(
        type: MealType,
        items: [MealFoodItemInput],
        photo: Data?,
        source: MealSource,
        context: ModelContext
    ) async throws -> MealLog {
        let foodItems = items.map { MealFoodItem(from: $0) }
        let meal = MealLog(
            type: type,
            dayDate: Date(),
            source: source,
            photo: photo,
            items: foodItems
        )

        context.insert(meal)

        do {
            try context.save()
            logger.info("Logged \(type.rawValue) with \(items.count) items, \(String(format: "%.0f", meal.totalCalories)) cal")
        } catch {
            logger.error("Failed to save meal: \(error.localizedDescription)")
            throw error
        }

        // Sync to HealthKit (logMeal is already async)
        try? await syncToHealthKit(meal)

        return meal
    }

    // MARK: - Update Meal

    func updateMeal(_ meal: MealLog, items: [MealFoodItemInput], context: ModelContext) throws {
        // Remove existing items
        for item in meal.items {
            context.delete(item)
        }

        // Add new items
        let foodItems = items.map { MealFoodItem(from: $0) }
        meal.items = foodItems
        meal.recalculateTotals()
        meal.syncedToHealthKit = false

        try context.save()
        logger.info("Updated \(meal.mealType.rawValue): \(items.count) items, \(String(format: "%.0f", meal.totalCalories)) cal")
    }

    // MARK: - Delete Meal

    func deleteMeal(_ meal: MealLog, context: ModelContext) throws {
        let mealType = meal.mealType.rawValue
        context.delete(meal)
        try context.save()
        logger.info("Deleted \(mealType)")
    }

    // MARK: - Fetch Today's Meals

    func fetchTodayMeals(context: ModelContext) -> [MealLog] {
        fetchMeals(for: Date(), context: context)
    }

    // MARK: - Fetch Meals for Date

    func fetchMeals(for date: Date, context: ModelContext) -> [MealLog] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let predicate = #Predicate<MealLog> { meal in
            meal.dayDate == startOfDay
        }
        let descriptor = FetchDescriptor<MealLog>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.loggedAt, order: .forward)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch meals: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Today Summary

    func todaySummary(context: ModelContext) -> DailyNutritionSummary {
        let meals = fetchTodayMeals(context: context)

        let totalCal = meals.reduce(0.0) { $0 + $1.totalCalories }
        let totalPro = meals.reduce(0.0) { $0 + $1.totalProtein }
        let totalCarbs = meals.reduce(0.0) { $0 + $1.totalCarbs }
        let totalFat = meals.reduce(0.0) { $0 + $1.totalFat }

        // Fetch targets from DailySnapshot if available
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let snapshotPredicate = #Predicate<DailySnapshot> { snapshot in
            snapshot.date == startOfDay
        }
        let snapshotDescriptor = FetchDescriptor<DailySnapshot>(predicate: snapshotPredicate)
        let snapshot = try? context.fetch(snapshotDescriptor).first

        return DailyNutritionSummary(
            date: startOfDay,
            totalCalories: totalCal,
            totalProtein: totalPro,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            mealsLogged: meals.count,
            calorieTarget: snapshot?.calorieTarget.map { Double($0) },
            proteinTarget: snapshot?.proteinTarget,
            carbsTarget: snapshot?.carbsTarget,
            fatTarget: snapshot?.fatTarget
        )
    }

    // MARK: - Sync to HealthKit

    // Write meal as HKCorrelation via HealthKitServiceProtocol.writeNutrition.

    func syncToHealthKit(_ meal: MealLog) async throws {
        guard !meal.syncedToHealthKit else {
            return
        }

        let sample = NutritionSample(
            date: meal.loggedAt,
            calories: meal.totalCalories,
            proteinGrams: meal.totalProtein,
            carbsGrams: meal.totalCarbs,
            fatGrams: meal.totalFat
        )

        do {
            try await healthKit.writeNutrition(sample)
            meal.syncedToHealthKit = true
            logger.info("Synced \(meal.mealType.rawValue) to HealthKit: \(String(format: "%.0f", meal.totalCalories)) cal")
        } catch {
            logger.error("HealthKit sync failed for \(meal.mealType.rawValue): \(error.localizedDescription)")
            throw NutritionError.healthKitWriteFailed(error.localizedDescription)
        }
    }
}
