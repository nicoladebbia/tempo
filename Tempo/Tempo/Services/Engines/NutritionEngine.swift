//
// NutritionEngine.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation

// MARK: - NutritionMode

// Recovery-adjusted nutrition targets, meal timing, hydration, calorie balance, and AI coaching.
// Per MODULE_DASHBOARD.md — Fuel intelligence powered by recovery zone + training schedule.

enum NutritionMode: String {
    case repair // Red recovery: +15% protein, +10% calories
    case fuel // Green recovery + high strain planned: +20% carbs
    case rest // Rest day: -15% calories
    case standard // Normal day
}

// MARK: - UserGoal

enum UserGoal: String {
    case bulk
    case cut
    case maintain
}

// MARK: - AdjustedNutritionTargets

struct AdjustedNutritionTargets {
    let calorieTarget: Int
    let proteinTarget: Int
    let carbsTarget: Int
    let fatTarget: Int
    let hydrationTargetMl: Int
    let mode: NutritionMode
    let modeExplanation: String

    // Original base targets for comparison
    let baseCalorieTarget: Int
    let baseProteinTarget: Int
    let baseCarbsTarget: Int
    let baseFatTarget: Int
    let baseHydrationMl: Int
}

// MARK: - NutritionEngine

enum NutritionEngine {
    // MARK: - Recovery-Adjusted Targets (Task 1)

    /// Compute recovery-adjusted macro targets based on recovery zone, strain, and training schedule.
    static func adjustedTargets(
        baseCalories: Int,
        baseProtein: Int,
        baseCarbs: Int,
        baseFat: Int,
        recoveryZone: RecoveryZone?,
        currentStrain: Double?,
        isTrainingDay: Bool,
        isRestDay: Bool,
        baseHydrationMl: Int = 2500
    ) -> AdjustedNutritionTargets {
        var calories = baseCalories
        var protein = baseProtein
        var carbs = baseCarbs
        let fat = baseFat
        var hydration = baseHydrationMl
        let mode: NutritionMode
        let explanation: String

        if let zone = recoveryZone {
            switch zone {
            case .red:
                // Repair mode: body needs extra protein for recovery and more total energy
                protein = Int(Double(baseProtein) * 1.15)
                calories = Int(Double(baseCalories) * 1.10)
                hydration = Int(Double(baseHydrationMl) * 1.20)
                mode = .repair
                explanation = "Recovery is red. Extra protein and calories to accelerate repair."

            case .green where isTrainingDay:
                // Fuel mode: green recovery + training = load up on carbs
                carbs = Int(Double(baseCarbs) * 1.20)
                calories = baseCalories + (carbs - baseCarbs) * 4 // adjust calories for extra carbs
                hydration = Int(Double(baseHydrationMl) * 1.15)
                mode = .fuel
                explanation = "Green recovery + training day. Extra carbs to fuel performance."

            case .yellow where isTrainingDay:
                // Moderate: slight carb bump, no protein change
                carbs = Int(Double(baseCarbs) * 1.10)
                mode = .standard
                explanation = "Yellow recovery with training. Slight carb increase."

            default:
                if isRestDay {
                    calories = Int(Double(baseCalories) * 0.85)
                    carbs = Int(Double(baseCarbs) * 0.85)
                    mode = .rest
                    explanation = "Rest day. Reduced calories to match lower energy expenditure."
                } else {
                    mode = .standard
                    explanation = "Standard targets. No recovery adjustments needed."
                }
            }
        } else if isRestDay {
            calories = Int(Double(baseCalories) * 0.85)
            carbs = Int(Double(baseCarbs) * 0.85)
            mode = .rest
            explanation = "Rest day. Reduced calories to match lower energy expenditure."
        } else {
            mode = .standard
            explanation = "Standard targets. No recovery adjustments needed."
        }

        // High strain bonus hydration
        if let strain = currentStrain, strain > 14 {
            hydration = Int(Double(hydration) * 1.15)
        }

        return AdjustedNutritionTargets(
            calorieTarget: calories,
            proteinTarget: protein,
            carbsTarget: carbs,
            fatTarget: fat,
            hydrationTargetMl: hydration,
            mode: mode,
            modeExplanation: explanation,
            baseCalorieTarget: baseCalories,
            baseProteinTarget: baseProtein,
            baseCarbsTarget: baseCarbs,
            baseFatTarget: baseFat,
            baseHydrationMl: baseHydrationMl
        )
    }

    // MARK: - Macro Status Colors (Task 2)

    enum MacroStatus {
        case onTrack // green: 80-105% of target
        case behind // yellow: below 80% and time-proportional
        case over // red: above 105%

        var colorName: String {
            switch self {
            case .onTrack: "tempoSuccess"
            case .behind: "tempoWarning"
            case .over: "tempoError"
            }
        }
    }

    /// Determine macro status based on current vs target, factoring in time of day.
    static func macroStatus(current: Int, target: Int) -> MacroStatus {
        guard target > 0 else {
            return .onTrack
        }
        let ratio = Double(current) / Double(target)
        if ratio > 1.05 {
            return .over
        }

        // Factor in time of day: at 6PM, you should be ~75% done
        let hour = Calendar.current.component(.hour, from: Date())
        let dayProgress = max(0.1, Double(hour - 7) / 15.0) // 7 AM to 10 PM window
        let expectedRatio = min(dayProgress, 1.0)

        if ratio >= expectedRatio * 0.8 {
            return .onTrack
        }
        return .behind
    }

    /// Remaining macro text: "Need 45g more protein"
    static func remainingText(macroName: String, current: Int, target: Int) -> String? {
        let remaining = target - current
        guard remaining > 0 else {
            return nil
        }
        return "Need \(remaining)g more \(macroName.lowercased())"
    }

    // MARK: - Meal Timing Suggestions (Task 3)

    struct MealTimingSuggestion {
        let icon: String
        let text: String
        let priority: Int // lower = more urgent
    }

    /// Generate meal timing suggestions based on training schedule and wake time.
    static func mealTimingSuggestions(
        workoutName: String?,
        workoutStatus: DashboardWorkoutStatus,
        wakeTimeMinutes: Int,
        currentHour: Int? = nil
    ) -> [MealTimingSuggestion] {
        var suggestions: [MealTimingSuggestion] = []
        let hour = currentHour ?? Calendar.current.component(.hour, from: Date())
        let wakeHour = wakeTimeMinutes / 60

        // Pre-workout meal timing
        if let name = workoutName, workoutStatus == .planned {
            // Estimate workout at ~4-5 PM if no specific time
            let estimatedWorkoutHour = max(wakeHour + 8, 16) // Default to late afternoon

            let preWorkoutHour = estimatedWorkoutHour - 2
            if hour < preWorkoutHour {
                let timeString = formatHour(preWorkoutHour)
                suggestions.append(MealTimingSuggestion(
                    icon: "fork.knife",
                    text: "Eat a carb-rich meal by \(timeString) before your \(name) workout.",
                    priority: 1
                ))
            } else if hour >= preWorkoutHour, hour < estimatedWorkoutHour {
                suggestions.append(MealTimingSuggestion(
                    icon: "bolt.fill",
                    text: "Quick carbs now: banana, rice cake, or energy bar before \(name).",
                    priority: 0
                ))
            }
        }

        // Post-workout window
        if workoutStatus == .completed {
            suggestions.append(MealTimingSuggestion(
                icon: "clock.fill",
                text: "Log a protein-rich meal within 1h of finishing your workout.",
                priority: 0
            ))
        }

        // Morning protein
        if hour >= wakeHour, hour < wakeHour + 2 {
            suggestions.append(MealTimingSuggestion(
                icon: "sunrise.fill",
                text: "Start with 30-40g protein at breakfast to kickstart muscle protein synthesis.",
                priority: 2
            ))
        }

        // Evening reminder
        if hour >= 19, hour < 21 {
            suggestions.append(MealTimingSuggestion(
                icon: "moon.fill",
                text: "Last chance to hit your macro targets. Log dinner or a late snack.",
                priority: 3
            ))
        }

        return suggestions.sorted { $0.priority < $1.priority }
    }

    // MARK: - Calorie Balance (Task 5)

    struct CalorieBalance {
        let caloriesIn: Int
        let caloriesOut: Int // From active calories / strain
        let balance: Int // Positive = surplus, negative = deficit
        let balanceText: String
        let isHealthy: Bool // Context-dependent on goal

        var isPositive: Bool {
            balance >= 0
        }
    }

    /// Calculate calorie balance from consumed vs burned.
    static func calorieBalance(
        caloriesConsumed: Int,
        activeCalories: Int,
        bmr: Double?,
        isTrainingDay: Bool,
        goal: UserGoal = .maintain
    ) -> CalorieBalance {
        let estimatedBMR = Int(bmr ?? 1800)
        let totalOut = estimatedBMR + activeCalories
        let balance = caloriesConsumed - totalOut
        let absBalance = abs(balance)

        let text = if balance >= 0 {
            "+\(absBalance) kcal surplus"
        } else {
            "-\(absBalance) kcal deficit"
        }

        let isHealthy: Bool = switch goal {
        case .bulk:
            // Surplus of 200-500 is ideal for bulking
            balance >= 100 && balance <= 600
        case .cut:
            // Deficit of 300-700 is ideal for cutting
            balance <= -200 && balance >= -800
        case .maintain:
            // Within +/- 200 is maintenance
            absBalance <= 250
        }

        return CalorieBalance(
            caloriesIn: caloriesConsumed,
            caloriesOut: totalOut,
            balance: balance,
            balanceText: text,
            isHealthy: isHealthy
        )
    }

    // MARK: - AI Coach Messages (Task 6)

    /// Generate contextual nutrition coaching messages based on current macro status.
    static func coachingMessage(
        proteinCurrent: Int, proteinTarget: Int,
        carbsCurrent: Int, carbsTarget: Int,
        fatCurrent: Int, fatTarget: Int,
        caloriesCurrent: Int, calorieTarget: Int,
        isTrainingDay: Bool,
        recoveryZone: RecoveryZone?,
        mealsLogged: Int
    ) -> String {
        let proteinRemaining = proteinTarget - proteinCurrent
        let carbsRemaining = carbsTarget - carbsCurrent
        _ = fatTarget - fatCurrent // fatRemaining reserved for future use
        let caloriesRemaining = calorieTarget - caloriesCurrent
        let proteinRatio = proteinTarget > 0 ? Double(proteinCurrent) / Double(proteinTarget) : 0
        let carbsRatio = carbsTarget > 0 ? Double(carbsCurrent) / Double(carbsTarget) : 0
        let fatRatio = fatTarget > 0 ? Double(fatCurrent) / Double(fatTarget) : 0
        let calorieRatio = calorieTarget > 0 ? Double(caloriesCurrent) / Double(calorieTarget) : 0
        let hour = Calendar.current.component(.hour, from: Date())

        // Priority-ordered coaching messages

        // 1. No meals logged yet
        if mealsLogged == 0, hour >= 9 {
            return "No meals logged yet. You're behind. Log breakfast now and front-load your protein to stay on track."
        }

        // 2. Red recovery + low protein
        if recoveryZone == .red, proteinRatio < 0.6 {
            return "Recovery is red and protein is only at \(proteinCurrent)g. Your body needs repair fuel. Prioritize chicken, fish, or eggs in your next meal."
        }

        // 3. Training day with low carbs
        if isTrainingDay, carbsRatio < 0.5, hour >= 12 {
            return "Your carbs are at \(carbsCurrent)g on a training day. You need fuel to perform. Add rice, pasta, or sweet potato to your next meal."
        }

        // 4. Protein target hit
        if proteinRatio >= 1.0, carbsRatio < 0.8 {
            return "Protein target hit at \(proteinCurrent)g. Now focus on getting your remaining \(carbsRemaining)g carbs in."
        }

        // 5. All macros on track
        if proteinRatio >= 0.9, carbsRatio >= 0.9, fatRatio >= 0.85 {
            return "Dialed in. All macros are within 10% of target. This is what consistency looks like."
        }

        // 6. Over on fat
        if fatRatio > 1.15 {
            let overFat = fatCurrent - fatTarget
            return "Fat is \(overFat)g over target. Go lean for the rest of the day — grilled protein, vegetables, no sauces."
        }

        // 7. Over on calories
        if calorieRatio > 1.1 {
            return "You're \(caloriesCurrent - calorieTarget) kcal over target. No more calorie-dense foods today. Stick to lean protein and vegetables."
        }

        // 8. Low protein, specific suggestion
        if proteinRemaining > 30 {
            let chickenGrams = Int(Double(proteinRemaining) / 0.31) // ~31g protein per 100g chicken
            return "You've had \(proteinCurrent)g protein. Add \(chickenGrams)g chicken breast (\(proteinRemaining)g protein) to hit your target."
        }

        // 9. Low protein, close to target
        if proteinRemaining > 0, proteinRemaining <= 30 {
            return "Almost there — \(proteinRemaining)g protein to go. A Greek yogurt (15g) or protein shake (25g) closes the gap."
        }

        // 10. Evening, calories remaining
        if hour >= 18, caloriesRemaining > 300 {
            return "Still \(caloriesRemaining) kcal to go tonight. Don't underfuel — a solid dinner with protein and carbs will help recovery."
        }

        // 11. Morning, good start
        if hour < 12, mealsLogged >= 1, proteinRatio >= 0.25 {
            return "Good start. \(proteinCurrent)g protein logged this morning. Keep this pace and you'll hit all targets by dinner."
        }

        // 12. Rest day message
        if !isTrainingDay, calorieRatio >= 0.7 {
            return "Rest day — calories are at \(Int(calorieRatio * 100))%. Keep portions moderate. Recovery happens at the table, not just in bed."
        }

        // Default
        return "Stay on plan. You have \(caloriesRemaining) kcal and \(proteinRemaining)g protein remaining. Log your next meal."
    }

    // MARK: - Hydration (Task 4)

    struct HydrationStatus {
        let currentMl: Int
        let targetMl: Int
        let glasses: Int // 250ml per glass
        let targetGlasses: Int
        let progress: Double
        let isOnTrack: Bool
    }

    static func hydrationStatus(
        currentMl: Int,
        targetMl: Int
    ) -> HydrationStatus {
        let glasses = currentMl / 250
        let targetGlasses = targetMl / 250
        let progress = targetMl > 0 ? Double(currentMl) / Double(targetMl) : 0

        let hour = Calendar.current.component(.hour, from: Date())
        let dayProgress = max(0.1, Double(hour - 7) / 15.0)
        let isOnTrack = progress >= dayProgress * 0.7

        return HydrationStatus(
            currentMl: currentMl,
            targetMl: targetMl,
            glasses: glasses,
            targetGlasses: targetGlasses,
            progress: min(progress, 1.0),
            isOnTrack: isOnTrack
        )
    }

    // MARK: - Helpers

    private static func formatHour(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 {
            return "12:00 AM"
        }
        if h == 12 {
            return "12:00 PM"
        }
        if h < 12 {
            return "\(h):00 AM"
        }
        return "\(h - 12):00 PM"
    }
}
