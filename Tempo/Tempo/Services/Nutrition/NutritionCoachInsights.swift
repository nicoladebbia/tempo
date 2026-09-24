//
// NutritionCoachInsights.swift
// Tempo
//
// Real-AI layer behind the Nutrition Coach tab. The three coach sections
// (daily briefing, recovery-aware guidance, per-meal feedback) used to be
// local if/else templates while `NutritionCoachService` sat unused. This file
// wires them to the service:
//   - `CoachDayContext` / `CoachMealSnapshot`: plain value snapshots of the
//     canonical eaten PlannedMeals + targets (no SwiftData crosses the actor).
//   - `CoachInsightCache`: persisted per-calendar-day cache, one entry per
//     section (per meal for feedback) so the AI runs at most once a day each.
//   - `NutritionCoachInsightsModel`: @Observable per-section load state the
//     view renders (loading / loaded / fallback / failed). Fixed-text
//     templates stay in the view as the offline / AI-off fallback.
//

import Foundation
import os
import SwiftData

// MARK: - CoachMealSnapshot

/// One eaten meal, flattened for prompt building.
struct CoachMealSnapshot: Sendable, Equatable {
    let id: UUID
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    /// "HH:mm" — actual eaten time when known, otherwise the scheduled slot.
    let time: String
    let items: [String]
}

extension CoachMealSnapshot {
    @MainActor
    init(meal: PlannedMeal) {
        let time: String
        if let eatenAt = meal.actualEatenAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            time = formatter.string(from: eatenAt)
        } else {
            time = meal.scheduledTime
        }
        self.init(
            id: meal.id,
            name: meal.mealName,
            calories: meal.totalCalories,
            protein: meal.totalProtein,
            carbs: meal.totalCarbs,
            fat: meal.totalFat,
            time: time,
            items: meal.foods.map(\.name)
        )
    }
}

// MARK: - CoachDayContext

/// Today's nutrition state as the coach sees it. Built from the same numbers
/// the Today tab shows (NutritionTabViewModel totals + targets) so the AI
/// never quotes a different target than the screen.
struct CoachDayContext: Sendable {
    let eatenMeals: [CoachMealSnapshot]
    let caloriesConsumed: Double
    let proteinConsumed: Double
    let carbsConsumed: Double
    let fatConsumed: Double
    let calorieTarget: Double
    let proteinTarget: Double
    let carbsTarget: Double
    let fatTarget: Double
    let mealsPlanned: Int
    let recovery: WhoopRecoveryData?
    let sleep: WhoopSleepData?
    /// Today's plan day type ("Strength", "Rest", …) — nil without a plan.
    let trainingToday: String?
    let tomorrowTraining: String?

    var summary: DailyNutritionSummary {
        DailyNutritionSummary(
            date: Date(),
            totalCalories: caloriesConsumed,
            totalProtein: proteinConsumed,
            totalCarbs: carbsConsumed,
            totalFat: fatConsumed,
            mealsLogged: eatenMeals.count,
            calorieTarget: calorieTarget,
            proteinTarget: proteinTarget,
            carbsTarget: carbsTarget,
            fatTarget: fatTarget
        )
    }

    var target: ActiveNutritionTarget {
        ActiveNutritionTarget(
            calories: calorieTarget,
            proteinGrams: proteinTarget,
            carbsGrams: carbsTarget,
            fatGrams: fatTarget,
            mealsPerDay: max(mealsPlanned, eatenMeals.count)
        )
    }

    /// Recovery zone per AI_INTELLIGENCE_ENGINE.md §3.5 (same bands as the VM).
    var recoveryZone: String? {
        guard let score = recovery?.score else {
            return nil
        }
        if score >= 67 {
            return "green"
        }
        if score >= 34 {
            return "yellow"
        }
        return "red"
    }
}

// MARK: - CoachRecoveryGuidance

/// AI recovery guidance: a short paragraph plus 2-4 one-line tips (the tips
/// replace the fixed per-zone list when AI is on).
struct CoachRecoveryGuidance: Codable, Sendable, Equatable {
    let message: String
    let tips: [String]
}

// MARK: - NutritionCoachInsightProviding

/// The slice of the coach service the Coach tab needs. `NutritionCoachService`
/// conforms; tests inject a fake.
protocol NutritionCoachInsightProviding: Sendable {
    func dailyBriefing(_ day: CoachDayContext) async throws -> String
    func recoveryGuidance(_ day: CoachDayContext) async throws -> CoachRecoveryGuidance
    func mealFeedback(for meal: CoachMealSnapshot, day: CoachDayContext) async throws -> String
}

// MARK: - CoachInsightCache

/// Persisted once-per-day cache for coach AI output. Keyed by
/// `yyyy-MM-dd|section` so yesterday's briefing never shows today; entries
/// from other days are pruned on every write. Stored as one small JSON blob
/// in UserDefaults (no SwiftData model change).
struct CoachInsightCache {
    enum Section: Sendable, Equatable {
        case dailyBriefing
        case recoveryGuidance
        case mealFeedback(UUID)

        var keyComponent: String {
            switch self {
            case .dailyBriefing: "daily"
            case .recoveryGuidance: "recovery"
            case let .mealFeedback(id): "meal.\(id.uuidString)"
            }
        }
    }

    static let storageKey = "nutrition.coach.insightCache.v1"

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func string(for section: Section, on date: Date = Date()) -> String? {
        load()[key(section, date)]
    }

    func store(_ value: String, for section: Section, on date: Date = Date()) {
        let prefix = dayPrefix(date)
        // Keep only today's entries — the cache never grows past one day.
        var entries = load().filter { $0.key.hasPrefix(prefix) }
        entries[key(section, date)] = value
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func remove(_ section: Section, on date: Date = Date()) {
        var entries = load()
        entries.removeValue(forKey: key(section, date))
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Codable convenience for structured sections (recovery guidance).
    func value<T: Decodable>(_: T.Type, for section: Section, on date: Date = Date()) -> T? {
        guard let raw = string(for: section, on: date), let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func store(_ value: some Encodable, for section: Section, on date: Date = Date()) {
        guard let data = try? JSONEncoder().encode(value), let raw = String(data: data, encoding: .utf8) else {
            return
        }
        store(raw, for: section, on: date)
    }

    private func load() -> [String: String] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return entries
    }

    private func dayPrefix(_ date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: date))
        return String(format: "%04d-%02d-%02d|", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private func key(_ section: Section, _ date: Date) -> String {
        dayPrefix(date) + section.keyComponent
    }
}

// MARK: - CoachInsightState

/// Per-section render state. Every non-`loaded` state shows the fixed-text
/// template; `failed` adds an error line + retry under it.
enum CoachInsightState<Value: Equatable & Sendable>: Equatable, Sendable {
    /// Not requested yet (or no data to ask about) → template.
    case idle
    case loading
    case loaded(Value)
    /// AI off for this user (no Pro / no AI consent) or device offline → template, no error.
    case fallback
    /// Real failure → template + error message.
    case failed(String)

    var value: Value? {
        if case let .loaded(value) = self {
            return value
        }
        return nil
    }

    var isLoading: Bool {
        self == .loading
    }

    var errorMessage: String? {
        if case let .failed(message) = self {
            return message
        }
        return nil
    }
}

// MARK: - NutritionCoachInsightsModel

@Observable
@MainActor
final class NutritionCoachInsightsModel {
    private(set) var daily: CoachInsightState<String> = .idle
    private(set) var recovery: CoachInsightState<CoachRecoveryGuidance> = .idle
    private(set) var mealFeedback: [UUID: CoachInsightState<String>] = [:]

    /// Set once the backend says "no Pro / no AI consent" — every section then
    /// stays on its template for the rest of this model's life instead of
    /// hammering a gated endpoint.
    private(set) var isAIGated = false

    @ObservationIgnored
    private let cache: CoachInsightCache
    @ObservationIgnored
    private let now: () -> Date
    @ObservationIgnored
    private let logger = Logger.nutrition

    init(cache: CoachInsightCache = CoachInsightCache(), now: @escaping () -> Date = Date.init) {
        self.cache = cache
        self.now = now
    }

    /// Show today's cached AI output immediately (no network). Called on
    /// appear so a reopened Coach tab never flashes the template.
    func restoreFromCache(eatenMealIDs: [UUID]) {
        let today = now()
        if daily.value == nil, let text = cache.string(for: .dailyBriefing, on: today) {
            daily = .loaded(text)
        }
        if recovery.value == nil,
           let guidance = cache.value(CoachRecoveryGuidance.self, for: .recoveryGuidance, on: today)
        {
            recovery = .loaded(guidance)
        }
        for id in eatenMealIDs where mealFeedback[id]?.value == nil {
            if let text = cache.string(for: .mealFeedback(id), on: today) {
                mealFeedback[id] = .loaded(text)
            }
        }
    }

    // MARK: - Sections

    func loadDailyBriefing(
        _ day: CoachDayContext,
        provider: any NutritionCoachInsightProviding,
        isOnline: Bool,
        force: Bool = false
    ) async {
        let today = now()
        if !force, let cached = cache.string(for: .dailyBriefing, on: today) {
            daily = .loaded(cached)
            return
        }
        guard canCallAI(isOnline: isOnline) else {
            daily = .fallback
            return
        }
        daily = .loading
        do {
            let text = try await provider.dailyBriefing(day)
            cache.store(text, for: .dailyBriefing, on: today)
            daily = .loaded(text)
        } catch {
            // A .task(id:) restart (e.g. Whoop recovery arriving mid-call)
            // cancels this request; APIClient rewraps that as a timeout /
            // network error, so check the task, not the error type. The
            // restarted load owns the section state now.
            guard !Task.isCancelled else { return }
            daily = failureState(for: error, section: "daily_briefing")
        }
    }

    /// No-op without Whoop recovery — the template's "Connect Whoop" copy is
    /// the right answer there and there's nothing for the AI to reason about.
    func loadRecoveryGuidance(
        _ day: CoachDayContext,
        provider: any NutritionCoachInsightProviding,
        isOnline: Bool,
        force: Bool = false
    ) async {
        guard day.recovery != nil else {
            recovery = .idle
            return
        }
        let today = now()
        if !force, let cached = cache.value(CoachRecoveryGuidance.self, for: .recoveryGuidance, on: today) {
            recovery = .loaded(cached)
            return
        }
        guard canCallAI(isOnline: isOnline) else {
            recovery = .fallback
            return
        }
        recovery = .loading
        do {
            let guidance = try await provider.recoveryGuidance(day)
            cache.store(guidance, for: .recoveryGuidance, on: today)
            recovery = .loaded(guidance)
        } catch {
            // A .task(id:) restart (e.g. Whoop recovery arriving mid-call)
            // cancels this request; APIClient rewraps that as a timeout /
            // network error, so check the task, not the error type. The
            // restarted load owns the section state now.
            guard !Task.isCancelled else { return }
            recovery = failureState(for: error, section: "recovery_guidance")
        }
    }

    /// Feedback for every eaten meal that doesn't have one yet today.
    /// Sequential so a gate/offline hit on the first meal stops the rest.
    func loadMealFeedback(
        for meals: [CoachMealSnapshot],
        day: CoachDayContext,
        provider: any NutritionCoachInsightProviding,
        isOnline: Bool
    ) async {
        let today = now()
        for meal in meals {
            if let cached = cache.string(for: .mealFeedback(meal.id), on: today) {
                mealFeedback[meal.id] = .loaded(cached)
                continue
            }
            if mealFeedback[meal.id]?.value != nil {
                continue
            }
            guard canCallAI(isOnline: isOnline) else {
                mealFeedback[meal.id] = .fallback
                continue
            }
            mealFeedback[meal.id] = .loading
            do {
                let text = try await provider.mealFeedback(for: meal, day: day)
                cache.store(text, for: .mealFeedback(meal.id), on: today)
                mealFeedback[meal.id] = .loaded(text)
            } catch {
                guard !Task.isCancelled else {
                    mealFeedback[meal.id] = nil
                    return
                }
                mealFeedback[meal.id] = failureState(for: error, section: "meal_feedback")
            }
        }
    }

    func feedbackState(for mealID: UUID) -> CoachInsightState<String> {
        mealFeedback[mealID] ?? .idle
    }

    // MARK: - Helpers

    private func canCallAI(isOnline: Bool) -> Bool {
        isOnline && !isAIGated
    }

    private func failureState<V>(for error: Error, section: String) -> CoachInsightState<V> {
        if error is CancellationError {
            return .idle
        }
        if let coachError = error as? NutritionCoachError, coachError.isEntitlementGate {
            isAIGated = true
            return .fallback
        }
        logger.warning("[coach] \(section, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        return .failed(error.localizedDescription)
    }
}

// MARK: - NutritionCoachService + NutritionCoachInsightProviding

extension NutritionCoachService: NutritionCoachInsightProviding {
    func dailyBriefing(_ day: CoachDayContext) async throws -> String {
        let prompt = NutritionCoachPrompts.dailySummaryPrompt(
            meals: day.eatenMeals.map {
                (type: $0.name, calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, time: $0.time)
            },
            totalCalories: day.caloriesConsumed,
            totalProtein: day.proteinConsumed,
            totalCarbs: day.carbsConsumed,
            totalFat: day.fatConsumed,
            calorieTarget: day.calorieTarget,
            proteinTarget: day.proteinTarget,
            carbsTarget: day.carbsTarget,
            fatTarget: day.fatTarget,
            mealsLogged: day.eatenMeals.count,
            mealsPlanned: day.target.mealsPerDay,
            recoveryScore: day.recovery?.score,
            recoveryZone: day.recoveryZone,
            tomorrowTraining: day.tomorrowTraining,
            dayInProgress: true,
            trainingToday: day.trainingToday
        )
        return try await coachText(prompt: prompt, maxTokens: 300, temperature: 0.4, feature: "daily_briefing", minWords: 15, maxWords: 100)
    }

    func recoveryGuidance(_ day: CoachDayContext) async throws -> CoachRecoveryGuidance {
        guard let recovery = day.recovery, let zone = day.recoveryZone else {
            throw NutritionCoachError.unavailable("Connect Whoop to get recovery-aware guidance.")
        }
        let prompt = NutritionCoachPrompts.recoveryNutritionPrompt(
            recoveryScore: recovery.score,
            recoveryZone: zone,
            hrvRmssd: recovery.hrvRmssd,
            restingHeartRate: recovery.restingHeartRate,
            sleepHours: day.sleep?.totalHours,
            sleepScore: day.sleep.map(\.sleepScore),
            todayCalories: day.caloriesConsumed,
            todayProtein: day.proteinConsumed,
            todayCarbs: day.carbsConsumed,
            todayFat: day.fatConsumed,
            calorieTarget: day.calorieTarget,
            proteinTarget: day.proteinTarget,
            trainingToday: day.trainingToday,
            withTips: true
        )
        let raw = try await coachRaw(prompt: prompt, maxTokens: 350, temperature: 0.3, feature: "recovery_guidance")
        let parsed = try Self.parseRecoveryGuidance(raw)
        return CoachRecoveryGuidance(
            message: trimToWordLimit(parsed.message, maxWords: 80),
            tips: Array(parsed.tips.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(4))
        )
    }

    func mealFeedback(for meal: CoachMealSnapshot, day: CoachDayContext) async throws -> String {
        let prompt = NutritionCoachPrompts.mealFeedbackPrompt(
            mealType: meal.name,
            mealCalories: meal.calories,
            mealProtein: meal.protein,
            mealCarbs: meal.carbs,
            mealFat: meal.fat,
            mealItems: meal.items.isEmpty ? meal.name : meal.items.joined(separator: ", "),
            todayCalories: day.caloriesConsumed,
            todayProtein: day.proteinConsumed,
            todayCarbs: day.carbsConsumed,
            todayFat: day.fatConsumed,
            todayMealsLogged: day.eatenMeals.count,
            calorieTarget: day.calorieTarget,
            proteinTarget: day.proteinTarget,
            carbsTarget: day.carbsTarget,
            fatTarget: day.fatTarget,
            mealsPerDay: day.target.mealsPerDay,
            recoveryZone: day.recoveryZone,
            trainingToday: day.trainingToday
        )
        return try await coachText(prompt: prompt, maxTokens: 150, temperature: 0.4, feature: "meal_feedback", minWords: 5, maxWords: 60)
    }

    /// Decode `{"message": …, "tips": […]}`, tolerating markdown fences /
    /// preamble around the object. A plain-text reply (model ignored the JSON
    /// instruction) still yields a usable message with no tips.
    nonisolated static func parseRecoveryGuidance(_ response: String) throws -> CoachRecoveryGuidance {
        let decoder = JSONDecoder()
        if let data = response.data(using: .utf8), let parsed = try? decoder.decode(CoachRecoveryGuidance.self, from: data) {
            return parsed
        }
        if let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"), start < end,
           let data = String(response[start ... end]).data(using: .utf8),
           let parsed = try? decoder.decode(CoachRecoveryGuidance.self, from: data)
        {
            return parsed
        }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("{") else {
            throw NutritionCoachError.invalidResponse("recovery_guidance")
        }
        return CoachRecoveryGuidance(message: trimmed, tips: [])
    }
}
