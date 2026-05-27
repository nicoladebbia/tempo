//
// DashboardQuadrantData.swift
// Tempo
//
// Extracted from DashboardViewModel.swift to keep that file under the
// SwiftLint file-length cap. Contains the value types the dashboard
// uses to render each quadrant + the dashboard's load state and
// biometric source enums. Pure data — no SwiftUI / SwiftData /
// HealthKit imports beyond what the structs themselves need.
//

import Foundation
import SwiftData

// MARK: - DashboardLoadState

enum DashboardLoadState {
    case loading
    case loaded
    case error(String)
}

// MARK: - BiometricDataSource

enum BiometricDataSource: String {
    case whoop = "Whoop"
    case healthKit = "HealthKit"
    case none = ""
}

// MARK: - BodyQuadrantData

struct BodyQuadrantData {
    var recoveryScore: Double?
    var hrv: Double?
    var rhr: Double?
    var sleepHours: Double?
    var sleepPerformance: Double?
    var strain: Double?
    var spo2: Double?
    var isConnected: Bool
    var lastSync: Date?
    var dataSource: BiometricDataSource = .none

    var recoveryZone: RecoveryZone? {
        recoveryScore.map { RecoveryZone(score: $0) }
    }

    var isStale: Bool {
        guard let lastSync else {
            return false
        }
        return Date().timeIntervalSince(lastSync) > 1800 // 30 min
    }

    // MARK: - Formatted Display Values

    var formattedRecovery: String {
        guard let recoveryScore else {
            return "--"
        }
        return "\(Int(recoveryScore))%"
    }

    var formattedHRV: String {
        guard let hrv else {
            return "--"
        }
        return String(format: "%.1f ms", hrv)
    }

    var formattedRHR: String {
        guard let rhr else {
            return "--"
        }
        return "\(Int(rhr)) bpm"
    }

    var formattedSleep: String {
        guard let sleepHours else {
            return "--"
        }
        return String(format: "%.1fh", sleepHours)
    }

    var formattedSleepPerformance: String {
        guard let sleepPerformance else {
            return "--"
        }
        return "\(Int(sleepPerformance))%"
    }

    var formattedStrain: String {
        guard let strain else {
            return "--"
        }
        return String(format: "%.1f", strain)
    }

    var formattedSpo2: String {
        guard let spo2 else {
            return "--"
        }
        return "\(Int(spo2))%"
    }

    static let empty = BodyQuadrantData(
        isConnected: false
    )
}

// MARK: - FuelQuadrantData

struct FuelQuadrantData {
    var caloriesConsumed: Int?
    var calorieTarget: Int?
    var proteinGrams: Int?
    var proteinTarget: Int?
    var carbsGrams: Int?
    var carbsTarget: Int?
    var fatGrams: Int?
    var fatTarget: Int?
    var mealsLogged: Int?
    var mealsPlanned: Int?
    var isConnected: Bool
    var lastSync: Date?

    var isStale: Bool {
        guard let lastSync else {
            return false
        }
        return Date().timeIntervalSince(lastSync) > 1200 // 20 min
    }

    var calorieProgress: Double {
        guard let consumed = caloriesConsumed, let target = calorieTarget, target > 0 else {
            return 0
        }
        return Double(consumed) / Double(target)
    }

    // MARK: - Recovery-Adjusted Targets (NutritionEngine)

    var adjustedTargets: AdjustedNutritionTargets?
    var nutritionMode: NutritionMode {
        adjustedTargets?.mode ?? .standard
    }

    var modeExplanation: String {
        adjustedTargets?.modeExplanation ?? ""
    }

    // MARK: - Hydration Tracking

    var hydrationMl: Int = 0
    var hydrationTargetMl: Int {
        adjustedTargets?.hydrationTargetMl ?? 2500
    }

    var hydrationProgress: Double {
        guard hydrationTargetMl > 0 else {
            return 0
        }
        return Double(hydrationMl) / Double(hydrationTargetMl)
    }

    var hydrationGlasses: Int {
        hydrationMl / 250
    }

    var hydrationTargetGlasses: Int {
        hydrationTargetMl / 250
    }

    // MARK: - Calorie Balance

    var activeCaloriesBurned: Int?
    var estimatedBMR: Double?

    // MARK: - Meal Timing

    var mealTimingSuggestions: [NutritionEngine.MealTimingSuggestion] = []

    // MARK: - AI Coaching

    var coachingMessage: String?

    // MARK: - Next Meal (Phase B)

    /// The upcoming `PlannedMeal` to surface in the Fuel quadrant. Nil when
    /// no plan exists, all meals already eaten/skipped, or the day's meals
    /// have all elapsed.
    var nextMeal: PlannedMeal?

    // MARK: - Last Meal Timestamp

    /// Most recent eat-time across today's PlannedMeal.actualEatenAt and
    /// MealLog.loggedAt rows. Drives the "Last meal Xh ago" line in the
    /// Fuel card. Nil when nothing logged yet today.
    var lastEatenAt: Date?

    /// Compact "Xh ago" / "X min ago" / "just now" / "—" formatter for
    /// the Fuel card subhead. Recomputes on every read; SwiftUI's
    /// `TimelineView(.everyMinute)` in the dashboard refreshes it.
    var formattedLastEaten: String {
        guard let last = lastEatenAt else { return "—" }
        let seconds = max(0, Date().timeIntervalSince(last))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        let remMin = minutes % 60
        return remMin == 0 ? "\(hours)h ago" : "\(hours)h \(remMin)m ago"
    }

    // MARK: - Macro Status

    var proteinStatus: NutritionEngine.MacroStatus {
        NutritionEngine.macroStatus(current: proteinGrams ?? 0, target: proteinTarget ?? 180)
    }

    var carbsStatus: NutritionEngine.MacroStatus {
        NutritionEngine.macroStatus(current: carbsGrams ?? 0, target: carbsTarget ?? 280)
    }

    var fatStatus: NutritionEngine.MacroStatus {
        NutritionEngine.macroStatus(current: fatGrams ?? 0, target: fatTarget ?? 80)
    }

    // MARK: - Formatted Display Values

    var formattedCalories: String {
        guard let caloriesConsumed else {
            return "--"
        }
        return NumberFormatter.localizedString(from: NSNumber(value: caloriesConsumed), number: .decimal)
    }

    var formattedCalorieTarget: String {
        guard let calorieTarget else {
            return "--"
        }
        return NumberFormatter.localizedString(from: NSNumber(value: calorieTarget), number: .decimal)
    }

    var formattedProtein: String {
        guard let proteinGrams else {
            return "--"
        }
        return "\(proteinGrams)g"
    }

    var formattedProteinTarget: String {
        guard let proteinTarget else {
            return "--"
        }
        return "\(proteinTarget)g"
    }

    var formattedCarbs: String {
        guard let carbsGrams else {
            return "--"
        }
        return "\(carbsGrams)g"
    }

    var formattedCarbsTarget: String {
        guard let carbsTarget else {
            return "--"
        }
        return "\(carbsTarget)g"
    }

    var formattedFat: String {
        guard let fatGrams else {
            return "--"
        }
        return "\(fatGrams)g"
    }

    var formattedFatTarget: String {
        guard let fatTarget else {
            return "--"
        }
        return "\(fatTarget)g"
    }

    var formattedMeals: String {
        guard let logged = mealsLogged, let planned = mealsPlanned else {
            return "--"
        }
        if logged >= planned {
            return "All \(planned) meals logged"
        }
        return "\(logged)/\(planned) meals"
    }

    var formattedHydration: String {
        "\(hydrationGlasses)/\(hydrationTargetGlasses) glasses"
    }

    /// Empty placeholder used before the first refresh completes.
    /// `nonisolated(unsafe)` because `FuelQuadrantData` now contains a SwiftData
    /// `PlannedMeal?` (non-Sendable). All real access is main-actor-isolated.
    nonisolated(unsafe) static let empty = FuelQuadrantData(
        isConnected: false
    )

    // MARK: - Mutating Helpers

    mutating func addHydration(_ ml: Int) {
        hydrationMl += ml
    }
}

// MARK: - MindQuadrantData

struct MindQuadrantData {
    var studyMinutesToday: Int
    var studyTargetMinutes: Int
    var currentStreakDays: Int
    var exams: [ExamData]

    var studyProgress: Double {
        guard studyTargetMinutes > 0 else {
            return 1.0
        }
        return Double(studyMinutesToday) / Double(studyTargetMinutes)
    }

    // MARK: - Formatted Display Values

    var formattedStudyTime: String {
        if studyMinutesToday >= 60 {
            let hours = studyMinutesToday / 60
            let minutes = studyMinutesToday % 60
            return "\(hours)h \(minutes)m"
        }
        return "\(studyMinutesToday)m"
    }

    var formattedStudyTarget: String {
        if studyTargetMinutes >= 60 {
            let hours = studyTargetMinutes / 60
            let minutes = studyTargetMinutes % 60
            if minutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(minutes)m"
        }
        return "\(studyTargetMinutes)m"
    }

    var formattedStreak: String {
        "\(currentStreakDays)d"
    }

    static let empty = MindQuadrantData(
        studyMinutesToday: 0,
        studyTargetMinutes: 120,
        currentStreakDays: 0,
        exams: []
    )
}

// MARK: - ExamData

struct ExamData: Identifiable {
    let id = UUID()
    let name: String
    let date: Date

    var daysUntil: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date))
            .day ?? 0
    }

    var formattedCountdown: String {
        switch daysUntil {
        case 0: "TODAY"
        case 1: "TOMORROW"
        default: "in \(daysUntil) days"
        }
    }
}

// MARK: - DashboardWorkoutStatus

/// Dashboard-specific workout display state.
/// Maps from the canonical `WorkoutStatus` model enum but adds rest-day / no-workout states
/// that only exist at the presentation layer.
enum DashboardWorkoutStatus {
    case completed
    case planned
    case restDay
    case none
}

// MARK: - MoveQuadrantData

struct MoveQuadrantData {
    var workoutStatus: DashboardWorkoutStatus
    var workoutName: String?
    var workoutDurationMinutes: Int?
    var steps: Int?
    var stepsTarget: Int
    var activeCalories: Int?
    var strain: Double?
    var heartRateCurrent: Int?
    var isConnected: Bool
    var lastSync: Date?

    var stepsProgress: Double {
        guard let steps, stepsTarget > 0 else {
            return 0
        }
        return Double(steps) / Double(stepsTarget)
    }

    var isStale: Bool {
        guard let lastSync else {
            return false
        }
        return Date().timeIntervalSince(lastSync) > 600 // 10 min for HR
    }

    // MARK: - Formatted Display Values

    var formattedSteps: String {
        guard let steps else {
            return "--"
        }
        return NumberFormatter.localizedString(from: NSNumber(value: steps), number: .decimal)
    }

    var formattedActiveCalories: String {
        guard let activeCalories else {
            return "--"
        }
        return "\(activeCalories) cal"
    }

    var formattedStrain: String {
        guard let strain else {
            return "--"
        }
        return String(format: "%.1f", strain)
    }

    var formattedHeartRate: String {
        guard let heartRateCurrent else {
            return "--"
        }
        return "\(heartRateCurrent) bpm"
    }

    var formattedWorkoutDuration: String {
        guard let minutes = workoutDurationMinutes else {
            return "--"
        }
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    static let empty = MoveQuadrantData(
        workoutStatus: .none,
        stepsTarget: 10000,
        isConnected: false
    )
}

// MARK: - NonNegotiableItem

struct NonNegotiableItem: Identifiable {
    let id: UUID
    let title: String
    var isCompleted: Bool
    let category: NonNegotiableCategory
}

// MARK: - NonNegotiableCategory

enum NonNegotiableCategory: String {
    case body
    case fuel
    case mind
    case move
}
