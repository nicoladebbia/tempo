import Foundation
import SwiftUI

// MARK: - Dashboard State

enum DashboardLoadState: Sendable {
    case loading
    case loaded
    case error(String)
}

// MARK: - Quadrant Data

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

    var recoveryZone: RecoveryZone? {
        recoveryScore.map { RecoveryZone(score: $0) }
    }

    var isStale: Bool {
        guard let lastSync else { return false }
        return Date().timeIntervalSince(lastSync) > 1800 // 30 min
    }

    // MARK: - Formatted Display Values

    var formattedRecovery: String {
        guard let recoveryScore else { return "--" }
        return "\(Int(recoveryScore))%"
    }

    var formattedHRV: String {
        guard let hrv else { return "--" }
        return String(format: "%.1f ms", hrv)
    }

    var formattedRHR: String {
        guard let rhr else { return "--" }
        return "\(Int(rhr)) bpm"
    }

    var formattedSleep: String {
        guard let sleepHours else { return "--" }
        return String(format: "%.1fh", sleepHours)
    }

    var formattedSleepPerformance: String {
        guard let sleepPerformance else { return "--" }
        return "\(Int(sleepPerformance))%"
    }

    var formattedStrain: String {
        guard let strain else { return "--" }
        return String(format: "%.1f", strain)
    }

    var formattedSpo2: String {
        guard let spo2 else { return "--" }
        return "\(Int(spo2))%"
    }

    static let empty = BodyQuadrantData(
        isConnected: false
    )
}

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
        guard let lastSync else { return false }
        return Date().timeIntervalSince(lastSync) > 1200 // 20 min
    }

    var calorieProgress: Double {
        guard let consumed = caloriesConsumed, let target = calorieTarget, target > 0 else { return 0 }
        return Double(consumed) / Double(target)
    }

    // MARK: - Formatted Display Values

    var formattedCalories: String {
        guard let caloriesConsumed else { return "--" }
        return NumberFormatter.localizedString(from: NSNumber(value: caloriesConsumed), number: .decimal)
    }

    var formattedCalorieTarget: String {
        guard let calorieTarget else { return "--" }
        return NumberFormatter.localizedString(from: NSNumber(value: calorieTarget), number: .decimal)
    }

    var formattedProtein: String {
        guard let proteinGrams else { return "--" }
        return "\(proteinGrams)g"
    }

    var formattedProteinTarget: String {
        guard let proteinTarget else { return "--" }
        return "\(proteinTarget)g"
    }

    var formattedCarbs: String {
        guard let carbsGrams else { return "--" }
        return "\(carbsGrams)g"
    }

    var formattedCarbsTarget: String {
        guard let carbsTarget else { return "--" }
        return "\(carbsTarget)g"
    }

    var formattedFat: String {
        guard let fatGrams else { return "--" }
        return "\(fatGrams)g"
    }

    var formattedFatTarget: String {
        guard let fatTarget else { return "--" }
        return "\(fatTarget)g"
    }

    var formattedMeals: String {
        guard let logged = mealsLogged, let planned = mealsPlanned else { return "--" }
        if logged >= planned {
            return "All \(planned) meals logged"
        }
        return "\(logged)/\(planned) meals"
    }

    static let empty = FuelQuadrantData(
        isConnected: false
    )
}

struct MindQuadrantData {
    var studyMinutesToday: Int
    var studyTargetMinutes: Int
    var currentStreakDays: Int
    var exams: [ExamData]

    var studyProgress: Double {
        guard studyTargetMinutes > 0 else { return 1.0 }
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
            if minutes == 0 { return "\(hours)h" }
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

struct ExamData: Identifiable {
    let id = UUID()
    let name: String
    let date: Date

    var daysUntil: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    var formattedCountdown: String {
        switch daysUntil {
        case 0: return "TODAY"
        case 1: return "TOMORROW"
        default: return "in \(daysUntil) days"
        }
    }
}

/// Dashboard-specific workout display state.
/// Maps from the canonical `WorkoutStatus` model enum but adds rest-day / no-workout states
/// that only exist at the presentation layer.
enum DashboardWorkoutStatus {
    case completed
    case planned
    case restDay
    case none
}

struct MoveQuadrantData {
    var workoutStatus: DashboardWorkoutStatus
    var workoutName: String?
    var workoutDurationMinutes: Int?
    var steps: Int?
    var stepsTarget: Int
    var activeCalories: Int?
    var heartRateCurrent: Int?
    var isConnected: Bool
    var lastSync: Date?

    var stepsProgress: Double {
        guard let steps, stepsTarget > 0 else { return 0 }
        return Double(steps) / Double(stepsTarget)
    }

    var isStale: Bool {
        guard let lastSync else { return false }
        return Date().timeIntervalSince(lastSync) > 600 // 10 min for HR
    }

    // MARK: - Formatted Display Values

    var formattedSteps: String {
        guard let steps else { return "--" }
        return NumberFormatter.localizedString(from: NSNumber(value: steps), number: .decimal)
    }

    var formattedActiveCalories: String {
        guard let activeCalories else { return "--" }
        return "\(activeCalories) cal"
    }

    var formattedHeartRate: String {
        guard let heartRateCurrent else { return "--" }
        return "\(heartRateCurrent) bpm"
    }

    var formattedWorkoutDuration: String {
        guard let minutes = workoutDurationMinutes else { return "--" }
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    static let empty = MoveQuadrantData(
        workoutStatus: .none,
        stepsTarget: 10_000,
        isConnected: false
    )
}

// MARK: - Non-Negotiable Display

struct NonNegotiableItem: Identifiable {
    let id: UUID
    let title: String
    var isCompleted: Bool
    let category: NonNegotiableCategory
}

enum NonNegotiableCategory: String, Sendable {
    case body, fuel, mind, move
}

// MARK: - Dashboard ViewModel

@Observable
@MainActor
final class DashboardViewModel {

    // MARK: - State

    private(set) var loadState: DashboardLoadState = .loading
    private(set) var snapshot: DailySnapshot?
    private(set) var lastRefresh: Date?

    // MARK: - Quadrant Data

    private(set) var body: BodyQuadrantData = .empty
    private(set) var fuel: FuelQuadrantData = .empty
    private(set) var mind: MindQuadrantData = .empty
    private(set) var move: MoveQuadrantData = .empty

    // MARK: - Non-Negotiables

    private(set) var nonNegotiables: [NonNegotiableItem] = []

    // MARK: - Daily Score

    var dailyScore: Int? {
        computeDailyScore()
    }

    var formattedDailyScore: String {
        guard let dailyScore else { return "--" }
        return "\(dailyScore)"
    }

    // MARK: - Greeting

    var greeting: String {
        greetingForCurrentTime(firstName: userName)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Dependencies

    private let healthKit: any HealthKitServiceProtocol
    private let whoop: any WhoopServiceProtocol
    private let nutriTrack: any NutriTrackServiceProtocol
    private var userName: String?

    // MARK: - Init

    init(services: ServiceContainer) {
        self.healthKit = services.healthKit
        self.whoop = services.whoop
        self.nutriTrack = services.nutriTrack
        self.userName = nil // Populated from UserProfile in later phases
    }

    // MARK: - Refresh
    // Per DATA_FLOW_ARCHITECTURE.md Section 2.1 — fetch from all sources concurrently.
    // HealthKit data is real; Whoop/NutriTrack via their service protocols.
    // Body quadrant: Whoop primary, HealthKit fallback for sleep/HRV/RHR.
    // Move quadrant: real steps, energy, workouts, HR from HealthKit.

    func refresh() async {
        loadState = .loading

        do {
            let today = Date()

            // Fetch all data sources concurrently
            async let whoopRecovery = whoop.fetchRecovery(for: today)
            async let whoopSleep = whoop.fetchSleep(for: today)
            async let whoopCycle = whoop.fetchCycle(for: today)
            async let hkSteps = healthKit.fetchSteps(for: today)
            async let hkActiveEnergy = healthKit.fetchActiveEnergy(for: today)
            async let hkHeartRate = healthKit.fetchHeartRate(for: today)
            async let hkHRV = healthKit.fetchHRV(for: today)
            async let hkRHR = healthKit.fetchRestingHeartRate(for: today)
            async let hkSleep = healthKit.fetchSleepAnalysis(for: today)
            async let hkWorkouts = healthKit.fetchWorkouts(for: today)
            async let nutriData = nutriTrack.fetchTodayMeals()

            let recovery = try await whoopRecovery
            let whoopSleepData = try await whoopSleep
            let cycle = try await whoopCycle
            let steps = try await hkSteps
            let energy = try await hkActiveEnergy
            let heartRates = try await hkHeartRate
            let hrv = try await hkHRV
            let rhr = try await hkRHR
            let hkSleepData = try await hkSleep
            let workouts = try await hkWorkouts
            let meals = try await nutriData

            let now = Date()
            let healthKitConnected = steps > 0 || !heartRates.isEmpty || hrv != nil

            // Build Body quadrant
            // Per INTEGRATION_SPECS.md: Whoop primary for recovery/HRV/RHR, HealthKit fallback.
            let sleepHours = whoopSleepData.totalHours > 0 ? whoopSleepData.totalHours : hkSleepData.totalHours
            let sleepPerf = whoopSleepData.sleepScore > 0 ? whoopSleepData.sleepScore : Double(hkSleepData.sleepScore)
            let bodyHRV = recovery.hrvRmssd ?? hrv
            let bodyRHR = recovery.restingHeartRate ?? rhr

            self.body = BodyQuadrantData(
                recoveryScore: recovery.score,
                hrv: bodyHRV,
                rhr: bodyRHR,
                sleepHours: sleepHours > 0 ? sleepHours : nil,
                sleepPerformance: sleepPerf > 0 ? sleepPerf : nil,
                strain: cycle.dayStrain,
                spo2: recovery.spo2,
                isConnected: recovery.score != nil || healthKitConnected,
                lastSync: now
            )

            // Build Fuel quadrant
            self.fuel = FuelQuadrantData(
                caloriesConsumed: Int(meals.totalCalories),
                calorieTarget: Int(meals.calorieTarget),
                proteinGrams: Int(meals.proteinGrams),
                proteinTarget: Int(meals.proteinTarget),
                carbsGrams: Int(meals.carbsGrams),
                carbsTarget: Int(meals.carbsTarget),
                fatGrams: Int(meals.fatGrams),
                fatTarget: Int(meals.fatTarget),
                mealsLogged: meals.mealsLogged,
                mealsPlanned: meals.mealsPlanned,
                isConnected: true,
                lastSync: now
            )

            // Build Mind quadrant (local data — stub values until Accountability module)
            self.mind = MindQuadrantData(
                studyMinutesToday: 95,
                studyTargetMinutes: 120,
                currentStreakDays: 12,
                exams: [
                    ExamData(name: "Calculus II", date: Date().addingTimeInterval(86400 * 6)),
                    ExamData(name: "Physics Lab", date: Date().addingTimeInterval(86400 * 14)),
                ]
            )

            // Build Move quadrant from real HealthKit data
            let latestHR = heartRates.last.map { Int($0.bpm) }
            let todaysWorkout = workouts.first
            let workoutStatus: DashboardWorkoutStatus
            let workoutName: String?
            let workoutDuration: Int?

            if let workout = todaysWorkout {
                workoutStatus = .completed
                workoutName = workout.workoutType.capitalized
                workoutDuration = Int(workout.durationMinutes)
            } else {
                workoutStatus = .none
                workoutName = nil
                workoutDuration = nil
            }

            self.move = MoveQuadrantData(
                workoutStatus: workoutStatus,
                workoutName: workoutName,
                workoutDurationMinutes: workoutDuration,
                steps: steps,
                stepsTarget: 10_000,
                activeCalories: Int(energy),
                heartRateCurrent: latestHR,
                isConnected: healthKitConnected || !workouts.isEmpty,
                lastSync: now
            )

            // Build non-negotiables (stub data until Accountability module)
            self.nonNegotiables = [
                NonNegotiableItem(id: UUID(), title: "Morning workout", isCompleted: todaysWorkout != nil, category: .body),
                NonNegotiableItem(id: UUID(), title: "Hit protein target", isCompleted: false, category: .fuel),
                NonNegotiableItem(id: UUID(), title: "2h study session", isCompleted: false, category: .mind),
                NonNegotiableItem(id: UUID(), title: "10k steps", isCompleted: steps >= 10_000, category: .move),
                NonNegotiableItem(id: UUID(), title: "8h sleep", isCompleted: sleepHours >= 8.0, category: .body),
            ]

            self.lastRefresh = now
            self.loadState = .loaded

        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Non-Negotiable Progress

    var nonNegotiablesDone: Int {
        nonNegotiables.filter(\.isCompleted).count
    }

    var nonNegotiablesTotal: Int {
        nonNegotiables.count
    }

    var nonNegotiableProgress: Double {
        guard nonNegotiablesTotal > 0 else { return 0 }
        return Double(nonNegotiablesDone) / Double(nonNegotiablesTotal)
    }

    // MARK: - Last Sync Display

    var formattedLastSync: String {
        guard let lastRefresh else { return "" }
        let interval = Date().timeIntervalSince(lastRefresh)
        if interval < 60 { return "Last sync: Just now" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "Last sync: \(minutes)m ago" }
        let hours = minutes / 60
        return "Last sync: \(hours)h ago"
    }

    // MARK: - Daily Score Calculation
    // Per MODULE_DASHBOARD.md Section 2.3

    private func computeDailyScore() -> Int? {
        struct Source {
            let isAvailable: Bool
            let rawScore: Double
        }

        // Recovery component
        let recoveryAvailable = body.isConnected && body.recoveryScore != nil
        let recoveryRaw = body.recoveryScore ?? 0

        // Nutrition component
        let nutritionAvailable = fuel.isConnected && fuel.caloriesConsumed != nil
        let nutritionRaw: Double = {
            guard let consumed = fuel.caloriesConsumed,
                  let target = fuel.calorieTarget, target > 0 else { return 0 }
            let base = min(100, (Double(consumed) / Double(target)) * 100)
            return max(0, base)
        }()

        // Study component
        let studyAvailable = true // Local data always available
        let studyRaw: Double = {
            guard mind.studyTargetMinutes > 0 else { return 100 }
            return min(100, (Double(mind.studyMinutesToday) / Double(mind.studyTargetMinutes)) * 100)
        }()

        // Movement component
        let movementAvailable = move.isConnected
        let movementRaw: Double = {
            let stepsComponent: Double = {
                guard let steps = move.steps, move.stepsTarget > 0 else { return 0 }
                return min(50, (Double(steps) / Double(move.stepsTarget)) * 50)
            }()
            let workoutComponent: Double = move.workoutStatus == .completed ? 50 : 0
            return min(100, stepsComponent + workoutComponent)
        }()

        let sources = [
            Source(isAvailable: recoveryAvailable, rawScore: recoveryRaw),
            Source(isAvailable: nutritionAvailable, rawScore: nutritionRaw),
            Source(isAvailable: studyAvailable, rawScore: studyRaw),
            Source(isAvailable: movementAvailable, rawScore: movementRaw),
        ]

        let connected = sources.filter(\.isAvailable)
        guard connected.count >= 2 else { return nil }

        let baseWeight = 0.25
        let missingCount = 4 - connected.count
        let extraPerSource = (baseWeight * Double(missingCount)) / Double(connected.count)

        var score = 0.0
        for source in connected {
            score += source.rawScore * (baseWeight + extraPerSource)
        }

        let clamped = max(0, min(100, score))
        guard !clamped.isNaN && !clamped.isInfinite else { return nil }
        return Int(round(clamped))
    }

    // MARK: - Greeting
    // Per UX_COPY_BIBLE.md Section 3.2

    private func greetingForCurrentTime(firstName: String?) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = firstName.map { ", \($0)" } ?? ""

        switch hour {
        case 0..<4: return "You should be asleep\(name)."
        case 4..<8: return "Early bird gets the gains\(name)."
        case 8..<12: return "Rise and grind\(name)."
        case 12..<14: return "No half reps this afternoon\(name)."
        case 14..<17: return "Keep the pressure on\(name)."
        case 17..<21: return "Finish what you started\(name)."
        case 21..<24: return "Earn your sleep\(name)."
        default: return "Rise and grind\(name)."
        }
    }

    // MARK: - Preview Helper

    static func preview() -> DashboardViewModel {
        let vm = DashboardViewModel(services: .mock())
        vm.loadState = .loaded
        vm.lastRefresh = Date()
        vm.body = BodyQuadrantData(
            recoveryScore: 72, hrv: 48, rhr: 62, sleepHours: 7.2,
            sleepPerformance: 78, strain: 12.4, spo2: 97.5,
            isConnected: true, lastSync: Date()
        )
        vm.fuel = FuelQuadrantData(
            caloriesConsumed: 2100, calorieTarget: 2400,
            proteinGrams: 165, proteinTarget: 180,
            carbsGrams: 240, carbsTarget: 280,
            fatGrams: 72, fatTarget: 80,
            mealsLogged: 3, mealsPlanned: 4,
            isConnected: true, lastSync: Date()
        )
        vm.mind = MindQuadrantData(
            studyMinutesToday: 95, studyTargetMinutes: 120,
            currentStreakDays: 12,
            exams: [
                ExamData(name: "Calculus II", date: Date().addingTimeInterval(86400 * 6)),
                ExamData(name: "Physics Lab", date: Date().addingTimeInterval(86400 * 14)),
            ]
        )
        vm.move = MoveQuadrantData(
            workoutStatus: .completed, workoutName: "Upper Body Push",
            workoutDurationMinutes: 55, steps: 8432, stepsTarget: 10_000,
            activeCalories: 342, heartRateCurrent: 72,
            isConnected: true, lastSync: Date()
        )
        vm.nonNegotiables = [
            NonNegotiableItem(id: UUID(), title: "Morning workout", isCompleted: true, category: .body),
            NonNegotiableItem(id: UUID(), title: "Hit protein target", isCompleted: false, category: .fuel),
            NonNegotiableItem(id: UUID(), title: "2h study session", isCompleted: false, category: .mind),
            NonNegotiableItem(id: UUID(), title: "10k steps", isCompleted: true, category: .move),
            NonNegotiableItem(id: UUID(), title: "8h sleep", isCompleted: true, category: .body),
        ]
        return vm
    }
}
