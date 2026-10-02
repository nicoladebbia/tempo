//
// NutritionTabViewModel.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import os
import SwiftData
import SwiftUI

// MARK: - NutritionSection

enum NutritionSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case log = "Log"
    case coach = "Coach"
    case pantry = "Pantry"

    var id: String {
        rawValue
    }
}

// MARK: - NutritionLoadState

enum NutritionLoadState {
    case loading
    case loaded
    case error(String)
}

// MARK: - PantryGapAlert

/// Surfaced when a freshly-generated meal plan references ingredients the user
/// doesn't have in pantry. Includes the canonical names so the view can decide
/// whether to inline the list or just say "N items missing."
struct PantryGapAlert: Identifiable, Equatable {
    let id = UUID()
    let missingIngredients: [String]

    var summary: String {
        // "Missing" = not in the pantry = you need to BUY it. So this routes to
        // the grocery list, not the pantry (you don't already have these).
        if missingIngredients.count == 1 {
            return "This plan needs \(missingIngredients[0]), which isn't in your pantry. Add it to your grocery list?"
        }
        return "This plan needs \(missingIngredients.count) items you don't have in your pantry. Add them to your grocery list to buy?"
    }
}

// MARK: - NutritionTabViewModel

@Observable
@MainActor
final class NutritionTabViewModel {
    // MARK: - Phase 7 (pantry/grocery/recipe/receipt) — stored directly so

    // the lifetimes match `self`. Previously these lived in a static
    // `ObjectIdentifier`-keyed dictionary which leaked the state objects
    // and their services for every ViewModel instance.

    let pantryState = NutritionPantryState()
    let receiptState = NutritionReceiptState()
    let recipeState = NutritionRecipeState()
    let groceryState = NutritionGroceryState()
    /// Store Mode aisle-tick session + weekly spend history state — see
    /// NutritionTabViewModel+GroceryAdvanced.swift.
    let groceryStoreModeState = NutritionGroceryStoreModeState()

    var pantryService: (any PantryServiceProtocol)?
    var receiptService: (any ReceiptServiceProtocol)?
    var recipeService: (any RecipeServiceProtocol)?
    var groceryService: (any GroceryListServiceProtocol)?
    var intelligence: NutritionIntelligenceService?
    /// AI batch price estimator for grocery items with no purchase history —
    /// see NutritionTabViewModel+GroceryAdvanced.swift.
    var groceryPriceAIService: GroceryPriceAIService?
    /// ModelContext captured at Phase 7 attach. Used by addPantryItem to
    /// insert a PantryPriceEntry on manual adds (the pantry service's
    /// mergeOrCreate doesn't own price history). Set in attachPhase7Services.
    var pantryModelContext: ModelContext?

    // MARK: - Pantry Smarts (staples + use-it-up notifications)

    let stapleState = NutritionStapleState()
    var stapleService: (any StapleServiceProtocol)?
    /// Held so `reloadPantry()` can schedule/cancel the daily "Use it up"
    /// notification without threading `services` through every call site.
    var notificationsService: (any NotificationServiceProtocol)?

    // MARK: - Service instances

    /// Held as stored properties so tests can replace them (and so each
    /// call doesn't construct a fresh service object with its own logger
    /// and URLSession underneath). `@ObservationIgnored` is required
    /// because @Observable rejects `lazy`; these aren't view-bindable.
    /// Lazily constructed on first use because we need an APIClient (passed
    /// from the View layer) to proxy Claude calls through the backend.
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §3.
    @ObservationIgnored
    private var coachService: NutritionCoachService?
    /// Lazily constructed on first use because we need an APIClient (passed
    /// from the View layer) to proxy Claude calls through the backend.
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §3.
    @ObservationIgnored
    private var redistributionService: MealRedistributionService?

    // MARK: - Task lifecycle

    /// Stored handles for in-flight async work. Replacing a task cancels the
    /// prior one so a fast tab-switch or retry doesn't race two writes onto
    /// the same @Observable state.
    private var planGenerationTask: Task<Void, Never>?
    private var mealSuggestionsTask: Task<Void, Never>?
    private var recoveryLoadTask: Task<Void, Never>?

    // No deinit cancel: @MainActor properties can't be touched from a
    // nonisolated deinit. Replacement-cancel inside each launch site
    // covers the practical re-entry case (tab switch / refresh); the
    // remaining edge case (deallocation while a task is in flight) is
    // bounded by the [weak self] capture inside each Task.

    // MARK: - State

    private(set) var loadState: NutritionLoadState = .loading
    var selectedTab: NutritionSection = .today

    // MARK: - Data

    private(set) var todayMeals: [PlannedMeal] = []
    /// Maps `PlannedMeal.id` → true when at least one `MealFeedback` row
    /// exists for it. Drives the "review pending" badge on past meal cards
    /// and the inline edit affordance in the end-of-week review screen.
    private(set) var feedbackPresence: [UUID: Bool] = [:]
    private(set) var weeklyPlan: WeeklyMealPlan?
    private(set) var presets: [MealPreset] = []
    private(set) var dietaryProfile: DietaryProfile?

    // MARK: - Plan freshness

    /// True when the active plan was generated from training / diet-profile
    /// inputs that have since changed (see MealPlanInputsFingerprint).
    /// Drives the "Plan out of date" banner on Today.
    private(set) var isPlanOutOfDate: Bool = false

    /// Inputs fingerprint as of the last freshness check — what "setup
    /// changed" is measured against.
    private(set) var currentInputsFingerprint: String?

    /// The inputs fingerprint the user said "Not now" to. The update banner
    /// stays hidden until the inputs change again (a different fingerprint).
    private(set) var dismissedUpdateFingerprint: String? = UserDefaults.standard
        .string(forKey: NutritionTabViewModel.dismissedUpdateKey)

    static let dismissedUpdateKey = "nutrition.planUpdateDismissedFingerprint"

    /// "Your setup changed — update the rest of the week?" Setup edits never
    /// rebuild the plan behind the user's back: this banner asks first.
    var showPlanUpdateBanner: Bool {
        isPlanOutOfDate && dismissedUpdateFingerprint != currentInputsFingerprint
    }

    /// "Not now": hide the banner until the plan inputs change again.
    func dismissPlanUpdateBanner() {
        dismissedUpdateFingerprint = currentInputsFingerprint
        UserDefaults.standard.set(currentInputsFingerprint, forKey: Self.dismissedUpdateKey)
    }

    /// Inputs fingerprint of the generation currently running, if any.
    @ObservationIgnored
    private var inFlightFingerprint: String?

    // MARK: - Generation

    var isGeneratingPlan: Bool = false
    var planGenerationError: String?
    /// Set when the build failed because the user needs Pro or hasn't allowed
    /// AI features — waiting or retrying won't help, the view offers the fix.
    var planGenerationBlocker: PlanGenerationBlocker?

    /// Drill-sergeant phase label shown under the spinner ("Drafting the week…",
    /// "Writing recipes for every meal…", etc). Mirrors
    /// `MealPlanGeneratorService.state.statusLabel` via the onStatus callback.
    var planGenerationStatusLabel: String = ""

    /// Surfaced after `generatePlan` completes when the just-generated plan has
    /// ingredients not present in the user's pantry. Views observe this and
    /// present an alert/banner that deep-links to the Pantry tab.
    var pantryGapAlert: PantryGapAlert?

    // MARK: - Coaching

    var coachMessage: String?
    var isLoadingMealSuggestions: Bool = false
    var mealSuggestions: [MealSuggestion] = []
    var mealSuggestionError: String?
    /// Set when meal ideas are blocked by Pro / AI-off; the Nutrition root
    /// shows the shared alert with the fix.
    var mealSuggestionBlocker: AIBlocker?

    // MARK: - Recovery (Whoop)

    private(set) var todayRecovery: WhoopRecoveryData?
    private(set) var todaySleep: WhoopSleepData?
    private(set) var recoveryNutritionGuidance: String?
    private(set) var isLoadingRecovery: Bool = false

    /// Local MIRROR of `WhoopService.weeklyTDEEAverage` (the shared source of
    /// truth) so the sync target computeds can read it without a service
    /// handle. Populated in loadRecoveryData after ensureWeeklyTDEEAverage().
    /// The Dashboard Fuel surface reads the same service value, so both
    /// surfaces agree on the no-plan TDEE estimate. nil → calculator falls
    /// back to Mifflin/Katch cleanly.
    private(set) var cachedWhoopAvgTDEE: Double?

    // MARK: - Computed

    var todayCaloriesConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalCalories) }
    }

    /// Today's active carryover refund, fetched in loadToday. Stored so the
    /// target computeds stay pure (no fetch per access).
    private(set) var todayCarryover: MacroCarryoverService.DailyAdjustment = .zero

    /// Today's training / rest status, fetched in loadToday.
    private(set) var todayDayContext: DailyNutritionTargets.DayContext = .unknown

    /// THE canonical daily target (base + carryover + recovery/rest-day
    /// adjustment) — see DailyNutritionTargets. The rebalancer calls the
    /// fetching twin `DailyNutritionTargets.today(in:)`, which runs the same
    /// compute over the same inputs, so the ring and the rebalancer agree.
    var todayTargets: DailyNutritionTargets {
        DailyNutritionTargets.compute(
            todayMeals: todayMeals,
            dietaryProfile: dietaryProfile,
            whoopAvgTDEE: cachedWhoopAvgTDEE,
            carryover: todayCarryover,
            day: todayDayContext,
            recoveryScore: todayRecovery?.score
        )
    }

    /// Short explanation of why today's target moved off the base ("Rest day
    /// −15% · +150 kcal from yesterday"). nil on a plain day.
    var todayTargetNote: String? {
        todayTargets.note
    }

    var todayCalorieTarget: Int {
        todayTargets.calories
    }

    /// True when a generated plan covers today AND today actually has meals
    /// from it. Drives the no-plan empty state on the Today page: when false,
    /// the calorie/macro figures are a TDEE *estimate*, not a real plan
    /// target, and the UI should say so + offer to generate a plan.
    var hasActivePlanForToday: Bool {
        weeklyPlan?.coversToday == true && !todayMeals.isEmpty
    }

    /// The plan AI's supplement take/skip decisions for TODAY (empty when the
    /// user owns no supplements or no active plan covers today). Surfaced as
    /// "Today's supplements" on the Today tab.
    ///
    /// The plan keys its per-day maps by `dayIndex + 1` where dayIndex 0 =
    /// Monday (the plan's startDate is anchored to Monday in persistPlan). So
    /// the correct key for today is (days since startDate) + 1 — NOT
    /// `Calendar.component(.weekday)`, whose 1=Sunday numbering does not match
    /// the plan's Monday=1 convention.
    var todaySupplementDecisions: [SupplementDecision] {
        guard let plan = weeklyPlan, plan.coversToday else {
            return []
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: plan.startDate)
        let today = cal.startOfDay(for: Date())
        let daysSinceStart = cal.dateComponents([.day], from: start, to: today).day ?? 0
        guard daysSinceStart >= 0, daysSinceStart < 7 else {
            return []
        }
        let key = daysSinceStart + 1 // Monday=1 … Sunday=7
        return SupplementDecision.dedupedByName(plan.supplementDecisions[key] ?? [])
    }

    /// Today's full supplement schedule (`SupplementScheduleEngine`), sorted
    /// chronologically — every non-archived shelf item, take AND skip, timed
    /// by pin/override/plan-timing/kind-default. Unlike
    /// `todaySupplementDecisions` (plan-only, take rows only) this is shown
    /// whenever the shelf is non-empty, even with no active plan.
    func todaySupplementDoses(modelContext: ModelContext) -> [SupplementDose] {
        let supplements = (try? modelContext.fetch(
            FetchDescriptor<Supplement>(predicate: #Predicate<Supplement> { !$0.isArchived })
        )) ?? []
        guard !supplements.isEmpty else {
            return []
        }
        let context = SupplementDayContext.build(date: Date(), modelContext: modelContext)
        return SupplementScheduleEngine.schedule(supplements: supplements, context: context)
    }

    /// Names of supplements the user marked TAKEN today (start-of-day keyed).
    /// Drives the checkmark state on the Today supplement card.
    func takenSupplementsToday(modelContext: ModelContext) -> Set<String> {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<SupplementIntakeLog>(
            predicate: #Predicate<SupplementIntakeLog> { $0.day == today }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return Set(rows.map(\.supplementName))
    }

    /// IDs of shelf supplements marked TAKEN today. The Today card keys its
    /// checkmarks on this, not on names, so two same-named items don't share
    /// a tick.
    func takenSupplementIDsToday(modelContext: ModelContext) -> Set<UUID> {
        SupplementIntakeStore.takenIDs(on: Date(), in: modelContext)
    }

    /// Toggle "I took it" for a supplement today — idempotent. A row's
    /// existence means taken; tapping again (undo) deletes it (ALL matching
    /// rows, so a double-tap can't leave one an undo can't clear).
    ///
    /// Keyed by `supplementID` (falls back to the name for callers/rows that
    /// only know the name). Also applies the reorder decrement/undo
    /// (`SupplementReorderService`) when the shelf item is tracked, and posts
    /// `.tempoSupplementsChanged` so `SupplementReminderScheduler` rebuilds
    /// today's reminders (a taken dose needs no more nagging).
    func toggleSupplementTaken(supplementID: UUID?, name: String, modelContext: ModelContext) {
        SupplementIntakeStore.toggle(supplementID: supplementID, name: name, in: modelContext)
        HapticManager.lightImpact()
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }

    /// Name-only form kept for existing callers; resolves the shelf item by name.
    func toggleSupplementTaken(name: String, modelContext: ModelContext) {
        toggleSupplementTaken(supplementID: nil, name: name, modelContext: modelContext)
    }

    var todayProteinConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalProtein) }
    }

    var todayProteinTarget: Int {
        todayTargets.protein
    }

    var todayCarbsConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalCarbs) }
    }

    var todayCarbsTarget: Int {
        todayTargets.carbs
    }

    var todayFatConsumed: Int {
        todayMeals
            .filter { $0.status == .eaten }
            .reduce(0) { $0 + Int($1.totalFat) }
    }

    var todayFatTarget: Int {
        todayTargets.fat
    }

    var calorieProgress: Double {
        guard todayCalorieTarget > 0 else {
            return 0
        }
        return Double(todayCaloriesConsumed) / Double(todayCalorieTarget)
    }

    var hasProfile: Bool {
        dietaryProfile != nil
    }

    var sortedPresets: [MealPreset] {
        presets.sorted { $0.useCount > $1.useCount }
    }

    // MARK: - Load

    /// Look up the (single) UserSettings record so Plan generation can read
    /// trainingSplit + footballDays. Returns nil only on fresh installs that
    /// haven't completed onboarding — in which case the generator skips the
    /// schedule injection and falls back to its generic week.
    static func loadUserSettings(modelContext: ModelContext) -> UserSettings? {
        let descriptor = FetchDescriptor<UserSettings>()
        return try? modelContext.fetch(descriptor).first
    }

    /// Parse a "HH:mm" (or "H:mm") string into minutes-since-midnight for
    /// chronological sort. Returns nil for anything we can't read so
    /// malformed values sort to the end instead of corrupting the order.
    /// Locale-independent: we split on ":" and parse as integers directly,
    /// dodging any DateFormatter locale or 12-h-format weirdness.
    static func minutesOfDay(from hhmm: String) -> Int? {
        MealOrdering.minutesOfDay(from: hhmm)
    }

    func loadToday(modelContext: ModelContext) {
        loadState = .loading

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        // Fetch today's PlannedMeals. The `meal.mealPlan?.isActive == true`
        // clause is defense-in-depth: MealPlanGeneratorService now deletes
        // (not just deactivates) prior plans so cascade wipes their meals,
        // but if any orphan survives a future code path the filter prevents
        // ghost duplicates from polluting the Today view.
        do {
            // Predicate keeps only the date-range filter — SwiftData's
            // #Predicate parser is unreliable for optional-chain expressions
            // on to-one relationships (`meal.mealPlan?.isActive == true`
            // silently returns false for some not-yet-faulted relationships,
            // which is why an NL-logged PlannedMeal could persist but never
            // render). Active-plan filtering happens in Swift right after
            // the fetch where the relationship resolves reliably.
            //
            // Sort moves to Swift too so the scheduledTime string is parsed
            // for chronological order (lex sort fails on "9:00" vs "10:00"
            // when the AI generator drops the leading zero).
            let mealDescriptor = FetchDescriptor<PlannedMeal>(
                predicate: #Predicate<PlannedMeal> { meal in
                    meal.dayDate >= todayStart && meal.dayDate < tomorrowStart
                }
            )
            let allTodayMeals = try modelContext.fetch(mealDescriptor)
            // Keep AI-generated meals from the active plan AND user-logged
            // meals that aren't tied to any plan, in "HH:mm" order.
            todayMeals = Self.chronological(allTodayMeals.filter(CanonicalMeals.isCanonical))
            refreshFeedbackPresence(modelContext: modelContext)

            // Fetch the active WeeklyMealPlan that ACTUALLY covers today.
            // `isActive` alone is insufficient: a plan stays active until the
            // next generation deletes it, so an out-of-range past plan (e.g.
            // dated May 25–31 viewed on June 2) would otherwise read as the
            // current plan and drive a stale Today/Plan view. The date-range
            // filter (`coversToday`) runs in Swift after the fetch — the
            // bounds are non-optional start-of-day Dates so it's reliable.
            let planDescriptor = FetchDescriptor<WeeklyMealPlan>(
                predicate: #Predicate<WeeklyMealPlan> { plan in
                    plan.isActive == true
                },
                sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
            )
            let plans = try modelContext.fetch(planDescriptor)
            weeklyPlan = plans.first { $0.coversToday }

            // Fetch all presets
            let presetDescriptor = FetchDescriptor<MealPreset>(
                sortBy: [SortDescriptor(\.useCount, order: .reverse)]
            )
            presets = try modelContext.fetch(presetDescriptor)

            // Fetch dietary profile
            let profileDescriptor = FetchDescriptor<DietaryProfile>(
                predicate: #Predicate<DietaryProfile> { profile in
                    profile.isActive == true
                }
            )
            let profiles = try modelContext.fetch(profileDescriptor)
            dietaryProfile = profiles.first

            // Freeze each plan meal's baseline before anything (substitute,
            // rebalance, redistribution — some in other screens) can rewrite
            // its totals, so today's target stays the plan's allocation.
            let capturedCount = todayMeals.filter { $0.capturePlanBaselineIfNeeded() }.count
            if capturedCount > 0 {
                try? modelContext.save()
            }
            todayCarryover = MacroCarryoverService.activeAdjustmentForToday(in: modelContext)
            todayDayContext = DailyNutritionTargets.dayContext(in: modelContext)
            refreshPlanFreshness(modelContext: modelContext)

            loadState = .loaded
        } catch {
            loadState = .error("Failed to load nutrition data: \(error.localizedDescription)")
        }
    }

    // MARK: - Plan Freshness

    /// Compares the active plan's stamped inputs fingerprint with the current
    /// inputs. A plan from before fingerprints existed is adopted as current
    /// (we can't know what it was built from) and stamped.
    func refreshPlanFreshness(modelContext: ModelContext) {
        guard let plan = weeklyPlan else {
            isPlanOutOfDate = false
            return
        }
        let current = MealPlanInputsFingerprint.current(in: modelContext)
        currentInputsFingerprint = current
        guard let stamped = plan.inputsFingerprint else {
            plan.inputsFingerprint = current
            try? modelContext.save()
            isPlanOutOfDate = false
            return
        }
        isPlanOutOfDate = stamped != current
    }

    /// Called whenever a plan input may have changed (training settings,
    /// trainer program, diet profile) and on launch. Only reloads and flags
    /// the plan as out of date — it NEVER rebuilds it. Today shows an "update
    /// the rest of the week?" banner and the user decides.
    func checkPlanFreshness(modelContext: ModelContext) {
        guard !isGeneratingPlan else {
            return
        }
        loadToday(modelContext: modelContext)
    }

    // MARK: - Meal Actions

    /// Everything the shared eat/skip/undo path needs, fed with this view
    /// model's cached Whoop inputs so the rebalancer uses the Today-ring target.
    private func outcomeEnv(
        _ modelContext: ModelContext,
        _ notifications: (any NotificationServiceProtocol)?
    ) -> MealOutcomeService.Env {
        MealOutcomeService.Env(
            modelContext: modelContext,
            notifications: notifications ?? notificationsService,
            whoopAvgTDEE: cachedWhoopAvgTDEE,
            recoveryScore: todayRecovery?.score
        )
    }

    /// Marks a meal eaten through `MealOutcomeService.markEaten` — the single
    /// path Today, the detail screen and the Watch share (status, time, pantry
    /// decrement, shift, rebalance, reminders, Dashboard ping). `foods` /
    /// `substituteNote` = "ate something else" (the planned dish is remembered
    /// for Undo). Returns false when the save failed.
    @discardableResult
    func markMealEaten(
        _ meal: PlannedMeal,
        at eatenAt: Date = Date(),
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil,
        feel: MealFeel? = nil,
        satiety: MealSatiety? = nil,
        replacingWith foods: [PlannedFood]? = nil,
        substituteNote: String? = nil,
        pantry: MealOutcomeService.PantryUse = .plannedMeal
    ) -> Bool {
        do {
            try MealOutcomeService.markEaten(
                meal,
                at: eatenAt,
                feel: feel,
                satiety: satiety,
                replacingWith: foods,
                substituteNote: substituteNote,
                pantry: pantry,
                env: outcomeEnv(modelContext, notifications)
            )
        } catch {
            Logger.nutrition.error("[Diag.Eat] mark eaten failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        HapticManager.notification(.success)
        refreshTodayMeals(modelContext: modelContext)
        reapplyPantryToGrocery()
        return true
    }

    /// Undo / delete a logged or skipped meal via `MealOutcomeService.undo`: a
    /// plan slot returns to `.planned` with its original dish, a log the user
    /// added on top of the plan is removed. Returns the snapshot for the Undo
    /// toast (nil when the save failed).
    @discardableResult
    func undoMealEaten(
        _ meal: PlannedMeal,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil
    ) -> MealOutcomeService.LogSnapshot? {
        let mealID = meal.id
        if meal.isUnplannedLog, meal.status == .eaten {
            // Drop the row from the cached list before the model is deleted so
            // nothing renders a dead reference.
            todayMeals.removeAll { $0.id == mealID }
            feedbackPresence[mealID] = nil
        }
        let snapshot: MealOutcomeService.LogSnapshot?
        do {
            snapshot = try MealOutcomeService.undo(meal, env: outcomeEnv(modelContext, notifications))
        } catch {
            Logger.nutrition.error("[Diag.Undo] failed: \(error.localizedDescription, privacy: .public)")
            snapshot = nil
        }
        // No haptic here: the Undo toast the caller shows fires its own.
        refreshTodayMeals(modelContext: modelContext)
        reapplyPantryToGrocery()
        return snapshot
    }

    /// Re-applies a log removed by `undoMealEaten` (the Undo toast).
    @discardableResult
    func restoreLog(
        _ snapshot: MealOutcomeService.LogSnapshot,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil
    ) -> Bool {
        do {
            try MealOutcomeService.restore(snapshot, env: outcomeEnv(modelContext, notifications))
        } catch {
            Logger.nutrition.error("[Diag.Undo] restore failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        refreshTodayMeals(modelContext: modelContext)
        reapplyPantryToGrocery()
        return true
    }

    /// Re-reads today's meals and presets after a change made outside this
    /// view model (meal detail screen, Watch, Log tab).
    func refreshAfterMealChange(modelContext: ModelContext) {
        refreshTodayMeals(modelContext: modelContext)
        refreshPresets(modelContext: modelContext)
    }

    /// Forgets a meal that is about to be deleted elsewhere
    /// (`.tempoMealWillBeRemoved`).
    func dropFromToday(mealID: UUID) {
        todayMeals.removeAll { $0.id == mealID }
        feedbackPresence[mealID] = nil
    }

    @discardableResult
    func markMealSkipped(
        _ meal: PlannedMeal,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil
    ) -> Bool {
        do {
            try MealOutcomeService.skip(meal, env: outcomeEnv(modelContext, notifications))
        } catch {
            Logger.nutrition.error("[Diag.Skip] failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        HapticManager.lightImpact()
        refreshTodayMeals(modelContext: modelContext)
        reapplyPantryToGrocery()
        return true
    }

    // MARK: - Skip Redistribution (AI)

    /// Banner copy surfaced after a successful AI redistribution. Cleared
    /// by the view when dismissed. One sentence summarising the model's
    /// reasoning ("snack +200 kcal, dinner +150g protein — recovery is
    /// green, dinner alone can't absorb it").
    var lastRedistributionBanner: String?

    /// True while the redistribution call is in-flight. View shows a small
    /// spinner on the skipped card.
    var isRedistributing: Bool = false

    /// Run the AI redistribution for a just-skipped meal. Applies the
    /// per-meal additive deltas to the remaining `PlannedMeal`s in
    /// `todayMeals`, saves, and surfaces the model's reasoning via
    /// `lastRedistributionBanner`. Falls back to a deterministic
    /// proportional split when Claude is unreachable.
    func redistributeSkippedMacros(
        _ skipped: PlannedMeal,
        modelContext: ModelContext,
        apiClient: APIClient,
        recoveryScore: Double?,
        sleepHours: Double?,
        strain: Double?,
        dayType: String
    ) async {
        isRedistributing = true
        defer { isRedistributing = false }

        if redistributionService == nil {
            redistributionService = MealRedistributionService(apiClient: apiClient)
        }
        guard let redistribution = redistributionService else {
            return
        }
        let result = await MealOutcomeService.redistributeAfterSkip(
            skipped,
            service: redistribution,
            env: outcomeEnv(modelContext, nil),
            recoveryScore: recoveryScore,
            sleepHours: sleepHours,
            strain: strain,
            dayType: dayType
        )
        refreshTodayMeals(modelContext: modelContext)
        // Only claim a redistribution when one was actually applied.
        guard let result else {
            return
        }
        let sourceTag = result.source == .ai ? "Coach" : "Fallback"
        lastRedistributionBanner = "\(sourceTag): \(result.reasoning)"
        HapticManager.notification(.success)
    }

    // MARK: - Presets

    func savePreset(name: String, items: [PlannedFood], mealType: MealType, modelContext: ModelContext) {
        guard let preset = try? MealOutcomeService.savePreset(
            name: name, foods: items, mealType: mealType, modelContext: modelContext
        ) else {
            return
        }
        presets.append(preset)
        HapticManager.notification(.success)
    }

    /// "Save as preset" on a logged meal. False when it has no foods or the
    /// save failed.
    @discardableResult
    func savePreset(from meal: PlannedMeal, name: String, modelContext: ModelContext) -> Bool {
        let foods = meal.foods
        guard !foods.isEmpty,
              let preset = try? MealOutcomeService.savePreset(
                  name: name,
                  foods: foods,
                  mealType: MealType.inferred(fromName: meal.mealName) ?? .snack,
                  modelContext: modelContext
              )
        else {
            return false
        }
        presets.append(preset)
        HapticManager.notification(.success)
        return true
    }

    func deletePreset(_ preset: MealPreset, modelContext: ModelContext) {
        presets.removeAll { $0.id == preset.id }
        modelContext.delete(preset)
        try? modelContext.save()
        HapticManager.lightImpact()
    }

    func refreshPresets(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<MealPreset>(sortBy: [SortDescriptor(\.useCount, order: .reverse)])
        if let fetched = try? modelContext.fetch(descriptor) {
            presets = fetched
        }
    }

    /// Logs a preset through `EatenMealRecorder` — the same path as Quick Log:
    /// fills a matching planned slot (planned dish remembered, shift/rebalance
    /// run), merges into an eaten one, or becomes an unplanned log; legacy
    /// MealLog written, Dashboard pinged. Returns nil when the save failed
    /// (so the caller must not toast success).
    @discardableResult
    func logFromPreset(
        _ preset: MealPreset,
        modelContext: ModelContext,
        resolution: EatenMealRecorder.DuplicateResolution = .add,
        notifications: (any NotificationServiceProtocol)? = nil
    ) -> EatenMealRecorder.Result? {
        let result: EatenMealRecorder.Result
        do {
            result = try EatenMealRecorder.record(
                preset.foodItems,
                type: preset.mealType,
                eatenAt: Date(),
                source: .preset,
                resolution: resolution,
                modelContext: modelContext,
                notifications: notifications ?? notificationsService
            )
        } catch {
            Logger.nutrition.error("[Diag.Preset] log failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        preset.recordUse()
        try? modelContext.save()
        let known = todayMeals.contains { $0.id == result.meal.id }
        todayMeals = Self.chronological(known ? todayMeals : todayMeals + [result.meal])
        HapticManager.notification(.success)
        return result
    }

    /// Today's meal order: parsed "HH:mm" minutes-of-day, then meal number.
    /// Malformed times sort to the end. Shared by loadToday, refreshTodayMeals
    /// and logFromPreset so a new row lands where a reload would put it.
    static func chronological(_ meals: [PlannedMeal]) -> [PlannedMeal] {
        MealOrdering.chronological(meals)
    }

    // MARK: - Generate Plan

    func generatePlan(
        modelContext: ModelContext,
        whoop: any WhoopServiceProtocol,
        apiClient: APIClient,
        notifications: (any NotificationServiceProtocol)? = nil,
        intake: MealPlanIntake? = nil,
        // Real source of the week's training schedule (TrainingScheduleProvider) —
        // the same engine/HealthKit instances the live Training tab uses, so a
        // throwaway TrainingViewModel built from them reads identical settings/
        // persisted state. See the `trainingSchedule` enrichment below.
        trainingEngine: any TrainingEngineProtocol,
        healthKit: any HealthKitServiceProtocol
    ) {
        // CRITICAL: re-fetch the DietaryProfile from SwiftData rather than
        // trusting the VM's cached `dietaryProfile`. When the user edits
        // the profile in FuelSetupView and triggers regen, the
        // cached property still holds the pre-save snapshot — that's why
        // the projection screen and the actual plan disagreed on kcal
        // (the projection used the live @State values; the plan used the
        // VM's stale cache). Reading from SwiftData every regen makes
        // the two surfaces share the same inputs.
        let profileDescriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate<DietaryProfile> { $0.isActive == true }
        )
        guard let profile = (try? modelContext.fetch(profileDescriptor))?.first else {
            return
        }
        dietaryProfile = profile
        // Snapshot the inputs NOW — the plan is built from these, so this is
        // what gets stamped even if something changes mid-generation (that
        // change then correctly reads as out of date).
        let inputsFingerprint = MealPlanInputsFingerprint.current(in: modelContext)
        // A profile save fires both its save-and-generate callback and the
        // app-level `.tempoDietaryProfileChanged` handler. Whichever lands
        // second is asking for the exact plan already being built — don't
        // cancel and restart it. (Wizard runs carry a fresh intake and always
        // proceed.)
        if isGeneratingPlan, intake == nil, inFlightFingerprint == inputsFingerprint {
            return
        }
        inFlightFingerprint = inputsFingerprint

        isGeneratingPlan = true
        planGenerationError = nil
        planGenerationBlocker = nil
        HapticManager.lightImpact()

        planGenerationTask?.cancel()
        planGenerationTask = Task {
            do {
                // Per INTELLIGENCE_REMEDIATION_PLAN.md §3 — Claude calls proxy
                // through the backend; the generator needs the auth-attaching
                // APIClient instead of the deleted ClaudeAPIClient.
                let generator = MealPlanGeneratorService(apiClient: apiClient)

                // Whoop "TDEE" intentionally nil. The previous version
                // fed `cycle.caloriesBurned` — a SINGLE day's burned
                // calories — into TDEECalculator's `whoopAverageTDEE`
                // input, which expects a 7-day rolling average. The
                // formula `0.6 * (whoop * 0.9) + 0.4 * mifflin` then
                // dragged the resulting TDEE down to ~1900 on a lazy
                // day, even when the Mifflin baseline was ~2900. That's
                // why the projection said 3285 kcal but the plan came
                // out at ~2000. Until a proper 7-day average is wired
                // (would need fetchCycleBatch), we use Mifflin only —
                // identical to what the projection screen does.
                let whoopTDEE: Double? = nil

                let (enrichedIntake, whoopWakeMinutes) = await Self.planInputs(
                    intake: intake,
                    modelContext: modelContext,
                    whoop: whoop,
                    trainingEngine: trainingEngine,
                    healthKit: healthKit
                )

                // Server first: USDA-checked foods + grams solved to every
                // day's macros. Not deployed / failed → build on device.
                let plan: WeeklyMealPlan
                do {
                    plan = try await WeeklyPlanService.shared.buildNow(
                        weekStart: WeeklyPlanService.currentWeekStart(),
                        intake: enrichedIntake,
                        modelContext: modelContext,
                        deps: PlanDeps(apiClient: apiClient, whoop: whoop, trainingEngine: trainingEngine, healthKit: healthKit),
                        onStatus: { [self] label in
                            planGenerationStatusLabel = label
                        }
                    )
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    // Pro / AI consent: the device build asks the same backend
                    // and would fail the same way — surface it instead.
                    if PlanGenerationBlocker(error) != nil {
                        throw error
                    }
                    Logger.nutrition
                        .info("[Diag.Plan] server plan unavailable (\(error.localizedDescription, privacy: .public)) — building on device")
                    plan = try await generator.generateWeeklyPlan(
                        profile: profile,
                        whoopTDEE: whoopTDEE,
                        wakeMinutesOverride: whoopWakeMinutes,
                        modelContext: modelContext,
                        intake: enrichedIntake,
                        onStatus: { [self] state in
                            planGenerationStatusLabel = state.statusLabel
                        }
                    )
                }

                // Plan-gen's delete-and-reinsert of WeeklyMealPlan +
                // PlannedMeal rows leaves the `plan` local pointing at
                // an invalidated SwiftData ref under some timings. Re-
                // fetch by ID via the modelContext so every downstream
                // consumer (scheduleDefrostReminders, computePantryGap,
                // generateGroceryList) reads from a fresh ref. If the
                // re-fetch fails (shouldn't, but defensive) we skip the
                // post-gen passes rather than risk the crash.
                let planID = plan.id
                let planDesc = FetchDescriptor<WeeklyMealPlan>(
                    predicate: #Predicate<WeeklyMealPlan> { $0.id == planID }
                )
                guard let freshPlan = (try? modelContext.fetch(planDesc))?.first else {
                    if Task.isCancelled {
                        return
                    }
                    weeklyPlan = nil
                    loadToday(modelContext: modelContext)
                    isGeneratingPlan = false
                    inFlightFingerprint = nil
                    planGenerationStatusLabel = ""
                    HapticManager.notification(.success)
                    return
                }
                // Stamp what this plan was actually built from, even when
                // superseded — a late-finishing stale generation must read
                // as out of date, never be adopted as current.
                freshPlan.inputsFingerprint = inputsFingerprint
                try? modelContext.save()
                // Superseded by a newer generatePlan call — that task owns
                // the plan, spinner and in-flight state now.
                if Task.isCancelled {
                    return
                }
                weeklyPlan = freshPlan
                // Refresh todayMeals AFTER the plan re-fetch so the
                // cached array also holds fresh refs.
                loadToday(modelContext: modelContext)
                if let notifications {
                    scheduleDefrostReminders(
                        for: freshPlan,
                        notifications: notifications,
                        modelContext: modelContext
                    )
                }
                pantryGapAlert = computePantryGap(for: freshPlan, modelContext: modelContext)
                // Auto-build the grocery list now so the user doesn't have to
                // hunt for a Generate button after the plan lands. Non-fatal:
                // failures surface via groceryState.lastError, not the plan UI.
                generateGroceryList()
                // Readers that cache today's meals / supplement decisions
                // (Dashboard Fuel, supplement reminders) follow the rebuild.
                NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
                if let notifications {
                    SupplementReminderScheduler.reschedule(notifications: notifications, modelContext: modelContext)
                }
                isGeneratingPlan = false
                inFlightFingerprint = nil
                planGenerationStatusLabel = ""
                HapticManager.notification(.success)
            } catch {
                // Superseded by a newer generatePlan call — that task owns
                // the spinner/error state now.
                if Task.isCancelled {
                    return
                }
                isGeneratingPlan = false
                inFlightFingerprint = nil
                planGenerationStatusLabel = ""
                planGenerationBlocker = PlanGenerationBlocker(error)
                planGenerationError = PlanGenerationBlocker.message(for: error)
                HapticManager.notification(.error)
            }
        }
    }

    /// Rebuilds the rest of the week from today with the app's shared
    /// services (the "Update" button and the blocker card use this one entry).
    func rebuildRestOfWeek(modelContext: ModelContext, services: ServiceContainer) {
        generatePlan(
            modelContext: modelContext,
            whoop: services.whoop,
            apiClient: services.apiClient,
            notifications: services.notifications,
            trainingEngine: services.trainingEngine,
            healthKit: services.healthKit
        )
    }

    // MARK: - Server-built plan

    /// A plan the Sunday job saved while this screen wasn't generating it:
    /// adopt it and run the same post-plan passes as a Regenerate.
    func adoptActivePlan(modelContext: ModelContext, notifications: (any NotificationServiceProtocol)?) {
        guard !isGeneratingPlan else {
            return
        }
        let descriptor = FetchDescriptor<WeeklyMealPlan>(predicate: #Predicate { $0.isActive })
        guard let plan = (try? modelContext.fetch(descriptor))?.first else {
            return
        }
        weeklyPlan = plan
        loadToday(modelContext: modelContext)
        if let notifications {
            scheduleDefrostReminders(for: plan, notifications: notifications, modelContext: modelContext)
        }
        pantryGapAlert = computePantryGap(for: plan, modelContext: modelContext)
        generateGroceryList()
    }

    // MARK: - Plan inputs

    /// The intake a weekly plan is built from — persisted prefs (or the
    /// wizard's), the REAL training week, grocery prefs — plus last night's
    /// Whoop wake time. Shared by the in-app generate and the Sunday job.
    static func planInputs(
        intake: MealPlanIntake?,
        modelContext: ModelContext,
        whoop: any WhoopServiceProtocol,
        trainingEngine: any TrainingEngineProtocol,
        healthKit: any HealthKitServiceProtocol,
        week: Date = Date()
    ) async -> (intake: MealPlanIntake, whoopWakeMinutes: Int?) {
        // Whoop wake time → meal anchor. iOS won't share the Health
        // Sleep Schedule, but Whoop knows when the user actually
        // woke. Use last night's Whoop wake (minutes from midnight)
        // to anchor meal times; nil falls back to UserSettings wake.
        var whoopWakeMinutes: Int?
        if whoop.providesRealData,
           let sleep = try? await whoop.fetchSleep(for: Date()),
           let wake = sleep.wakeTime
        {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: wake)
            whoopWakeMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }

        // Enrich the intake with the user's actual weekly training
        // schedule from UserSettings so the AI generates day-types
        // that match Mon=Upper / Wed=Football reality rather than
        // a generic "Wed strength / Thu cardio" guess.
        // When the caller supplies a fresh intake (the wizard), use it.
        // Otherwise — the "Regenerate Plan" button and the other 3
        // non-wizard generate paths — load the user's PERSISTED prefs
        // instead of bare .default, so a quick regen respects their real
        // cooking days / leftover style / eating window / exclusions.
        let settingsForIntake = Self.loadUserSettings(modelContext: modelContext)
        // One permanent "won't eat" list (DietaryProfile.dislikedFoods): fold
        // in the retired AI Meals exclusions before the plan reads them.
        if let settingsForIntake {
            let activeProfile = (try? modelContext.fetch(
                FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })
            ))?.first
            if MealPlanIntake.migrateLegacyExclusions(settings: settingsForIntake, profile: activeProfile) {
                try? modelContext.save()
            }
        }
        let intakeSource: String
        var enrichedIntake: MealPlanIntake
        if let intake {
            enrichedIntake = intake
            intakeSource = "wizard"
        } else if let settingsForIntake {
            // Judge "this week's" wizard answers against the week being
            // built: Sunday's build of next week must not inherit them.
            enrichedIntake = MealPlanIntake.loadPersisted(from: settingsForIntake, now: week)
            intakeSource = "persisted"
        } else {
            enrichedIntake = .default
            intakeSource = "default"
        }
        let diagCookDays = enrichedIntake.cookableDaysThisWeek
        let diagLeftover = enrichedIntake.leftoverTolerance.rawValue
        let diagWindow = "\(enrichedIntake.eatingWindow.firstMealHour)-\(enrichedIntake.eatingWindow.lastMealHour)"
        let diagExclusions = enrichedIntake.temporaryExclusions.count
        Logger.nutrition
            .info(
                "[Diag.Plan] intake source: \(intakeSource, privacy: .public) — cookDays=\(diagCookDays) leftover=\(diagLeftover, privacy: .public) window=\(diagWindow, privacy: .public) exclusions=\(diagExclusions)"
            )
        if let settings = settingsForIntake {
            // Fix #3 — the settings-only guess (split + footballDays)
            // agreed with Training only in the simplest case. Pull the
            // REAL week (trainer program, matches, custom map, recovery
            // swaps included) from the same generation path the
            // Training tab uses, via TrainingScheduleProvider.
            let realWeek = TrainingScheduleProvider.weekSchedule(
                containing: week,
                trainingEngine: trainingEngine,
                whoop: whoop,
                healthKit: healthKit,
                modelContext: modelContext
            )
            enrichedIntake.trainingSchedule = WeeklyTrainingSchedule.build(from: realWeek)
            // Hydrate the persisted grocery preferences when the
            // caller didn't supply them (non-wizard regen) so the
            // Sonnet prompt always sees the latest budget cap +
            // store list. The wizard's own commitAndAdvance keeps
            // these in sync, so the values here are the source of
            // truth.
            let persistedGrocery = GroceryIntent(
                willShopThisWeek: enrichedIntake.groceryIntent?.willShopThisWeek ?? true,
                budgetCapUSD: settings.groceryBudgetCapUSD,
                preferredStores: settings.groceryPreferredStores
            )
            if let existing = enrichedIntake.groceryIntent {
                // Wizard already populated — only fill in blanks.
                var merged = existing
                if merged.budgetCapUSD == nil {
                    merged.budgetCapUSD = persistedGrocery.budgetCapUSD
                }
                if merged.preferredStores.isEmpty {
                    merged.preferredStores = persistedGrocery.preferredStores
                }
                enrichedIntake.groceryIntent = merged
            } else if persistedGrocery.budgetCapUSD != nil
                || !persistedGrocery.preferredStores.isEmpty
            {
                enrichedIntake.groceryIntent = persistedGrocery
            }
        }
        return (enrichedIntake, whoopWakeMinutes)
    }

    /// Compute the set of canonical ingredient names referenced by the plan that
    /// aren't present in the user's pantry. Returns nil when there's nothing
    /// missing — the view should suppress the alert in that case.
    private func computePantryGap(
        for plan: WeeklyMealPlan,
        modelContext: ModelContext
    ) -> PantryGapAlert? {
        // Snapshot pantry canonical names (in-stock items only).
        let descriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false && item.quantity > 0
            }
        )
        // Leftover "dust" from fractional containers isn't real stock.
        let pantryNames: Set<String> = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter(\.isInStock)
            .map(\.canonicalName)
            .reduce(into: Set<String>()) { acc, name in
                acc.insert(name.lowercased())
            }

        // Re-fetch the plan's PlannedMeals by ID rather than iterating
        // the plan's relationship, which can hold invalidated refs
        // right after persistPlan's delete-and-reinsert
        // ("BackingData.swift:1039 Fatal" otherwise).
        let planID = plan.id
        let mealDesc = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.mealPlan?.id == planID
            }
        )
        let meals = (try? modelContext.fetch(mealDesc)) ?? []
        var needed: Set<String> = []
        for meal in meals {
            for ingredient in meal.recipe?.ingredients ?? [] {
                needed.insert(ingredient.canonicalFoodName.lowercased())
            }
        }

        // Exclude staples + water from the "missing" count. The grocery list
        // already suppresses staples (you don't re-buy salt/oil/water every
        // week), but this gap calc was counting them — inflating the number
        // and producing nonsense like "missing: water". Mirror that gate here.
        let missing = needed
            .subtracting(pantryNames)
            .filter { name in
                if name == "water" {
                    return false
                }
                if let portion = FoodMacroDatabase.naturalPortions[name], portion.isStaple {
                    return false
                }
                return true
            }
            .sorted()
        guard !missing.isEmpty else {
            return nil
        }
        return PantryGapAlert(missingIngredients: missing)
    }

    /// Walk every PlannedMeal in `plan`, find ingredients that require a defrost
    /// reminder, and schedule a Time Sensitive notification at `mealTime − leadTime`.
    ///
    /// Clears EVERY pending defrost reminder first via `cancelCategory` so that
    /// a regenerated plan doesn't leak stale reminders from prior plans whose
    /// meals were deactivated but kept around as historical records (their
    /// PlannedMeal.id values are not in the new plan, so per-meal cancellation
    /// would miss them).
    private func scheduleDefrostReminders(
        for plan: WeeklyMealPlan,
        notifications: any NotificationServiceProtocol,
        modelContext: ModelContext
    ) {
        notifications.cancelCategory("DEFROST_REMINDER")
        notifications.cancelCategory("PREP_START_REMINDER")
        notifications.cancelCategory("OVERDUE_MEAL_REMINDER")
        let calendar = Calendar.current
        let now = Date()

        // Re-fetch meals by plan ID instead of reading `plan.meals`.
        // The relationship cache can contain invalidated PlannedMeal
        // refs right after persistPlan's delete-and-reinsert; the
        // fresh fetch is the only reliable read.
        let planID = plan.id
        let mealDesc = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.mealPlan?.id == planID
            }
        )
        let freshMeals = (try? modelContext.fetch(mealDesc)) ?? []

        // Snapshot every meal's notification-relevant fields before
        // any further SwiftData I/O.
        struct PendingNotification {
            let mealID: UUID
            let mealName: String
            let mealTime: Date
            let prepStart: Date
            let defrosts: [(id: UUID, name: String, lead: Int)]
        }
        // Eaten / skipped meals need no reminder (a from-today rebuild keeps them).
        let pending: [PendingNotification] = freshMeals.filter { $0.status == .planned || $0.status == .modified }.map { meal in
            let mealTime = MealScheduleHelpers.scheduledDate(for: meal, calendar: calendar)
            let prepStart = MealScheduleHelpers.prepStartDate(for: meal, calendar: calendar)
            let defrosts: [(UUID, String, Int)] = (meal.recipe?.ingredients ?? [])
                .filter(\.requiresDefrostReminder)
                .map { ($0.id, $0.displayName, $0.defrostLeadTimeHours) }
            return PendingNotification(
                mealID: meal.id,
                mealName: meal.mealName,
                mealTime: mealTime,
                prepStart: prepStart,
                defrosts: defrosts
            )
        }

        for item in pending {
            if item.prepStart > now, item.prepStart != item.mealTime {
                notifications.schedulePrepStartReminder(
                    mealID: item.mealID,
                    mealName: item.mealName,
                    prepStartDate: item.prepStart
                )
            }
            if item.mealTime > now {
                notifications.scheduleOverdueMealReminder(
                    mealID: item.mealID,
                    mealName: item.mealName,
                    scheduledTime: item.mealTime,
                    lateMinutes: 15
                )
            }
            for defrost in item.defrosts {
                guard let fireDate = calendar.date(byAdding: .hour, value: -defrost.lead, to: item.mealTime) else {
                    continue
                }
                guard fireDate > now else {
                    continue
                }
                notifications.scheduleDefrostReminder(
                    mealID: item.mealID,
                    ingredientID: defrost.id,
                    ingredientName: defrost.name,
                    mealName: item.mealName,
                    leadTimeHours: defrost.lead,
                    fireDate: fireDate
                )
            }
        }
        scheduleMealReminders(modelContext: modelContext, notifications: notifications)
    }

    // MARK: - Wizard Snapshot Builder

    /// Builds the launch snapshot the intake wizard needs to decide which steps to surface.
    /// Pantry state, Whoop yesterday's recovery, and basic profile reference. Never throws —
    /// any failure degrades to a "missing" field rather than blocking the wizard.
    func buildWizardSnapshot(
        modelContext: ModelContext,
        whoop: any WhoopServiceProtocol
    ) async -> WizardLaunchSnapshot {
        // Pantry snapshot
        let pantrySnapshot: PantrySnapshot
        let service = pantryService ?? LocalPantryService(modelContext: modelContext)
        if let items = try? service.fetchAll() {
            let mostRecent = items.map(\.updatedAt).max()
            pantrySnapshot = PantrySnapshot(itemCount: items.count, mostRecentUpdate: mostRecent)
        } else {
            pantrySnapshot = PantrySnapshot(itemCount: 0, mostRecentUpdate: nil)
        }

        // Whoop snapshot — non-throw == connected
        var whoopSnapshot: WhoopSnapshot?
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        if whoop.providesRealData, let recovery = try? await whoop.fetchRecovery(for: yesterday) {
            whoopSnapshot = WhoopSnapshot(recoveryScore: recovery.score)
        }

        return WizardLaunchSnapshot(
            pantry: pantrySnapshot,
            whoop: whoopSnapshot
        )
    }

    // MARK: - Meal Suggestions

    func getMealSuggestions(apiClient: APIClient) {
        isLoadingMealSuggestions = true
        mealSuggestionError = nil
        mealSuggestionBlocker = nil
        HapticManager.lightImpact()

        if coachService == nil {
            coachService = NutritionCoachService(apiClient: apiClient)
        }

        let remainingCal = Double(max(0, todayCalorieTarget - todayCaloriesConsumed))
        let remainingProtein = Double(max(0, todayProteinTarget - todayProteinConsumed))
        let remainingCarbs = Double(max(0, todayCarbsTarget - todayCarbsConsumed))
        let remainingFat = Double(max(0, todayFatTarget - todayFatConsumed))

        let budget = MacroBudget(
            caloriesRemaining: remainingCal,
            proteinRemaining: remainingProtein,
            carbsRemaining: remainingCarbs,
            fatRemaining: remainingFat,
            calorieTarget: Double(todayCalorieTarget),
            proteinTarget: Double(todayProteinTarget),
            carbsTarget: Double(todayCarbsTarget),
            fatTarget: Double(todayFatTarget)
        )

        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = if hour < 11 {
            "morning"
        } else if hour < 15 {
            "afternoon"
        } else if hour < 19 {
            "evening"
        } else {
            "night"
        }

        // Determine if training day based on today's plan meals count
        let isTrainingDay = !todayMeals.isEmpty

        mealSuggestionsTask?.cancel()
        guard let coach = coachService else {
            isLoadingMealSuggestions = false
            mealSuggestionError = "Coach unavailable"
            return
        }
        mealSuggestionsTask = Task { [coach] in
            do {
                let suggestions = try await coach.mealSuggestions(
                    remainingBudget: budget,
                    timeOfDay: timeOfDay,
                    isTrainingDay: isTrainingDay
                )
                mealSuggestions = suggestions
                isLoadingMealSuggestions = false
                HapticManager.notification(.success)
            } catch {
                isLoadingMealSuggestions = false
                mealSuggestionError = AIBlocker.message(for: error)
                mealSuggestionBlocker = AIBlocker(error)
                HapticManager.notification(.error)
            }
        }
    }

    // MARK: - Meal Reminders

    /// Pre-meal reminders (15 min before every planned meal, only while the
    /// Meal Reminders switch is on) follow the plan: called after every plan
    /// build / adoption. See `MealReminderPlanner`.
    func scheduleMealReminders(modelContext: ModelContext, notifications: any NotificationServiceProtocol) {
        MealReminderPlanner.reschedule(modelContext: modelContext, notifications: notifications)
    }

    // MARK: - Recovery Data

    func loadRecoveryData(whoop: any WhoopServiceProtocol) {
        isLoadingRecovery = true

        recoveryLoadTask?.cancel()
        recoveryLoadTask = Task {
            // Fetch recovery and sleep independently so a sleep failure
            // doesn't blank the recovery quadrant. Errors on either path
            // are logged rather than silently mapped to nil.
            do {
                todayRecovery = try await whoop.fetchRecovery(for: Date())
            } catch is CancellationError {
                isLoadingRecovery = false
                return
            } catch {
                Logger.nutrition.warning("Whoop recovery fetch failed: \(error.localizedDescription, privacy: .public)")
                todayRecovery = nil
            }
            do {
                todaySleep = try await whoop.fetchSleep(for: Date())
            } catch is CancellationError {
                isLoadingRecovery = false
                return
            } catch {
                Logger.nutrition.warning("Whoop sleep fetch failed: \(error.localizedDescription, privacy: .public)")
                todaySleep = nil
            }

            // Refresh the 7-day expenditure average on the SHARED WhoopService,
            // then mirror it locally for the sync target computeds. The service
            // is the single source of truth — the Dashboard Fuel surface reads
            // the same `whoop.weeklyTDEEAverage`, so the two surfaces can never
            // disagree on the no-plan TDEE estimate. ensureWeeklyTDEEAverage
            // never throws (logs + nils on failure), so no do/catch here.
            await whoop.ensureWeeklyTDEEAverage()
            cachedWhoopAvgTDEE = whoop.weeklyTDEEAverage

            isLoadingRecovery = false
        }
    }

    var recoveryScore: Double? {
        todayRecovery?.score
    }

    var recoveryZone: String? {
        guard let score = recoveryScore else {
            return nil
        }
        if score >= 67 {
            return "green"
        } else if score >= 34 {
            return "yellow"
        } else {
            return "red"
        }
    }

    // MARK: - Private

    private func refreshTodayMeals(modelContext: ModelContext) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        do {
            // Same shape as the primary loadToday fetch — Swift-side filter
            // and sort, simple predicate. See loadToday(modelContext:) for
            // why we don't do this in #Predicate.
            let descriptor = FetchDescriptor<PlannedMeal>(
                predicate: #Predicate<PlannedMeal> { meal in
                    meal.dayDate >= todayStart && meal.dayDate < tomorrowStart
                }
            )
            let allTodayMeals = try modelContext.fetch(descriptor)
            todayMeals = Self.chronological(allTodayMeals.filter(CanonicalMeals.isCanonical))
            refreshFeedbackPresence(modelContext: modelContext)
        } catch {
            // Silent refresh failure
        }
    }

    /// Rebuild `feedbackPresence` against the current `todayMeals`. Cheap
    /// (one fetch + dictionary build) and called from both `loadToday` and
    /// `refreshTodayMeals` so the UI always reflects the latest review
    /// state. Internal because the feedback sheet calls it via its
    /// onDismiss to clear the "review pending" badge immediately.
    func refreshFeedbackPresence(modelContext: ModelContext) {
        let mealIDs = Set(todayMeals.map(\.id))
        guard !mealIDs.isEmpty else {
            feedbackPresence = [:]
            return
        }
        // CRITICAL: do NOT iterate MealFeedback and read row.plannedMeal?.id.
        // The relationship can point at a PlannedMeal that was cascade-
        // deleted during plan regen — even with deleteRule: .nullify the
        // in-memory ref stays dangling until the next re-fault, and
        // accessing .id on the invalidated child crashes with
        // SwiftData "BackingData.swift:1039 Fatal".
        //
        // Instead, for each candidate mealID fetch MealFeedback rows
        // whose plannedMeal predicate matches that ID. SwiftData's
        // predicate engine handles the relationship safely server-side,
        // and any feedback rows tied to deleted meals (which can't
        // match a still-existing mealID) are skipped automatically.
        var presence: [UUID: Bool] = [:]
        for mealID in mealIDs {
            let descriptor = FetchDescriptor<MealFeedback>(
                predicate: #Predicate<MealFeedback> { row in
                    row.plannedMeal?.id == mealID
                }
            )
            if let count = try? modelContext.fetchCount(descriptor), count > 0 {
                presence[mealID] = true
            }
        }
        feedbackPresence = presence
    }

    // MARK: - Test Hooks (Phase 4)

    #if DEBUG
        /// Test-only setter for today's planned meals. NOT for production code.
        func _testSetTodayMeals(_ meals: [PlannedMeal]) {
            todayMeals = meals
        }

        /// Test-only setter for today's Whoop recovery data. NOT for production code.
        func _testSetTodayRecovery(_ recovery: WhoopRecoveryData?) {
            todayRecovery = recovery
        }

        /// Test-only setter for the active weekly plan. NOT for production code.
        func _testSetWeeklyPlan(_ plan: WeeklyMealPlan?) {
            weeklyPlan = plan
        }

        /// Test-only setter for today's carryover + day context. NOT for production code.
        func _testSetTargetInputs(
            carryover: MacroCarryoverService.DailyAdjustment,
            day: DailyNutritionTargets.DayContext
        ) {
            todayCarryover = carryover
            todayDayContext = day
        }
    #endif
}
