//
// NutritionTodayView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Nutrition Today View

// Today's meal plan with macro progress rings, calorie bar, and planned meal cards.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct NutritionTodayView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    /// Opens the Quick Log sheet (stays on Today).
    var onQuickLog: () -> Void = {}
    /// Opens the scanner. Owned by the tab root so it can be swapped in one place.
    var onScan: () -> Void = {}
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    /// When set, presents `MealFeedbackSheet` for this meal. Used by the
    /// review-pending chip on past eaten meals and the long-form review
    /// flow. NOT the path taken by a fresh mark-eaten tap — that goes
    /// through `markEatenMeal` below.
    @State
    private var feedbackMeal: PlannedMeal?
    /// Meal opened from a row tap (pushes MealDetailView).
    @State
    private var detailMeal: PlannedMeal?

    /// When set, presents `MarkEatenSheet` for this meal. Combines the
    /// backward-fill time scrubber and the meal-feel chip. Replaces the
    /// previous "tap = commits at .now" behavior — every Mark Eaten tap
    /// now opens this sheet first.
    @State
    private var markEatenMeal: PlannedMeal?

    /// Result toasts (errors, "log deleted" with Undo).
    @State
    private var toast: ToastData?
    /// Pro / AI-off while reading "what you ate": asks for the fix.
    @State
    private var substituteBlocker: AIBlocker?

    /// "Save as preset" naming alert.
    @State
    private var presetSourceMeal: PlannedMeal?
    @State
    private var presetNameDraft = ""

    /// Bumped after toggling a supplement "taken" so the card re-reads the
    /// taken set (a fetch in a computed view doesn't auto-refresh on insert).
    @State
    private var supplementTakenRefresh = 0
    /// Ties a meal card to the meal page that opens from it.
    @Namespace
    private var mealZoom

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Tide.s4) {
                    if viewModel.showPlanUpdateBanner {
                        PlanUpdateBanner(viewModel: viewModel)
                    }
                    if let banner = viewModel.lastRedistributionBanner {
                        redistributionBanner(banner)
                    }
                    heroCard
                    actionRow(scrollTo: { id in
                        withAnimation(Tide.settle) { proxy.scrollTo(id, anchor: .center) }
                    })
                    mealsListSection
                    WaterCardView()
                        .id(Self.waterID)
                    supplementsCard
                    RecoveryCoachCard()
                    UseUpSoonCard(viewModel: viewModel)

                    // AI disclaimer
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                        Image(systemName: "info.circle")
                            .font(Tide.caption)
                            .accessibilityHidden(true)
                        Text("AI-generated guidance. Not medical or dietetic advice. Consult a professional for personalized plans.")
                            .font(Tide.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Tide.text3)
                    .padding(.vertical, Tide.s2)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s8)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            // Meal logging now lives solely on the Log tab — the Today page's
            // floating "Log a Meal" FAB was removed (redundant entry point).
            .task {
                // Refresh pantry + recipe suggestions so UseUpSoonCard has FIFO-ranked
                // candidates without requiring a visit to the Recipes tab first.
                viewModel.reloadPantry()
                viewModel.refreshRecipeSuggestions()
            }
            // A "Taken" tapped on a notification (or a restock elsewhere) changes
            // the intake logs behind this card's fetch — re-read so the checkmark
            // is right and a second tap doesn't undo it.
            .onReceive(NotificationCenter.default.publisher(for: .tempoSupplementsChanged)) { _ in
                supplementTakenRefresh += 1
            }
            .navigationDestination(item: $detailMeal) { meal in
                // The meal page grows out of its card and shrinks back into it.
                MealDetailView(meal: meal)
                    .navigationTransition(.zoom(sourceID: meal.id, in: mealZoom))
            }
            .sheet(item: $feedbackMeal, onDismiss: {
                viewModel.refreshFeedbackPresence(modelContext: modelContext)
            }) { meal in
                MealFeedbackSheet(meal: meal)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $markEatenMeal) { meal in
                MarkEatenSheet(meal: meal) { eatTime, feel, satiety, substitute in
                    commitMarkEaten(meal: meal, at: eatTime, feel: feel, satiety: satiety, substitute: substitute)
                }
                .presentationDetents([.medium, .large])
            }
            .tempoToast($toast)
            .aiBlockerAlert($substituteBlocker)
            .alert("Save as preset", isPresented: Binding(
                get: { presetSourceMeal != nil },
                set: {
                    if !$0 {
                        presetSourceMeal = nil
                    }
                }
            )) {
                TextField("Preset name", text: $presetNameDraft)
                Button("Save") {
                    if let meal = presetSourceMeal {
                        let name = presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        let saved = !name.isEmpty
                            && viewModel.savePreset(from: meal, name: name, modelContext: modelContext)
                        toast = saved
                            ? ToastData(message: "\(name) saved. Find it on the Log tab.", style: .success)
                            : ToastData(message: "Couldn't save that preset.", style: .error)
                    }
                    presetSourceMeal = nil
                }
                Button("Cancel", role: .cancel) { presetSourceMeal = nil }
            } message: {
                Text("Log this meal again in one tap from the Log tab.")
            }
        }
    }

    // MARK: - Action row

    private static let waterID = "today.water"

    /// Four thumb-sized shortcuts at the top of Today.
    private func actionRow(scrollTo: @escaping (String) -> Void) -> some View {
        GlassEffectContainer(spacing: Tide.s2) {
            HStack(spacing: Tide.s2) {
                actionButton(icon: "text.bubble.fill", label: "Quick Log", id: "today.action.quicklog") {
                    onQuickLog()
                }
                actionButton(icon: "barcode.viewfinder", label: "Scan", id: "today.action.scan") {
                    onScan()
                }
                // One tap logs a glass; the water card (scrolled into view) shows
                // the new total and its Undo.
                actionButton(icon: "drop.fill", label: "+250 ml", id: "today.action.water", tint: Tide.water) {
                    WaterStore(context: modelContext, healthKit: services.healthKit).add(ml: 250)
                    scrollTo(Self.waterID)
                }
                actionButton(icon: "pills.fill", label: "Supps", id: "today.action.supplements") {
                    viewModel.openKitchen(.supplements)
                }
            }
        }
    }

    private func actionButton(
        icon: String, label: String, id: String, tint: Color? = nil, action: @escaping () -> Void
    ) -> some View {
        FuelActionTile(icon: icon, label: label, tint: tint, identifier: id) {
            HapticManager.lightImpact()
            action()
        }
        .accessibilityLabel(label == "Supps" ? "Supplements" : label == "+250 ml" ? "Log 250 ml of water" : label)
    }

    // MARK: - Undo / delete / preset

    /// Undo an eaten/skipped meal (plan slot → planned, ad-hoc log → deleted)
    /// with a 5-second Undo toast.
    private func undoMeal(_ meal: PlannedMeal) {
        let name = meal.mealName
        guard let snapshot = viewModel.undoMealEaten(
            meal, modelContext: modelContext, notifications: services.notifications
        )
        else {
            toast = ToastData(message: "Couldn't undo \(name). Try again.", style: .error)
            return
        }
        let message = snapshot.kind == .removed ? "\(name) log deleted." : "\(name) is back on the plan."
        toast = ToastData(message: message, style: .info, actionTitle: "Undo") {
            if !viewModel.restoreLog(snapshot, modelContext: modelContext, notifications: services.notifications) {
                toast = ToastData(message: "Couldn't restore \(name).", style: .error)
            }
        }
    }

    private func beginSavePreset(_ meal: PlannedMeal) {
        presetNameDraft = meal.foods.first.map { meal.foods.count > 1 ? "\($0.name) +\(meal.foods.count - 1)" : $0.name }
            ?? meal.mealName
        presetSourceMeal = meal
    }

    // MARK: - Hero

    /// Calories as the one big number, then the three macros: the same
    /// figures, colours and structure as the Fuel card on the Today tab.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(
                title: "Calories",
                trailing: FuelCalorieHero.remaining(
                    consumed: viewModel.todayCaloriesConsumed, target: viewModel.todayCalorieTarget
                )
            )
            VStack(alignment: .leading, spacing: Tide.s2) {
                FuelCalorieHero(consumed: viewModel.todayCaloriesConsumed, target: viewModel.todayCalorieTarget)
                Text(calorieQuip)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            FuelMacroColumns(
                protein: (viewModel.todayProteinConsumed, viewModel.todayProteinTarget),
                carbs: (viewModel.todayCarbsConsumed, viewModel.todayCarbsTarget),
                fat: (viewModel.todayFatConsumed, viewModel.todayFatTarget)
            )
            // Why today's target isn't the plain plan number — rest day,
            // recovery, or yesterday's refund. Same target the Dashboard shows.
            if let note = viewModel.todayTargetNote {
                Label(note, systemImage: "slider.horizontal.3")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .accessibilityLabel("Target adjusted: \(note)")
            }
        }
        .tideCard()
        .accessibilityIdentifier("fuel.hero")
    }

    // MARK: - Today's Supplements

    private var supplementsCard: some View {
        TodaySupplementsCard(viewModel: viewModel, refreshToken: supplementTakenRefresh)
    }

    private var calorieQuip: String {
        let ratio = viewModel.calorieProgress
        switch ratio {
        case ..<0.25: return "Empty tank, soldier."
        case 0.25 ..< 0.5: return "Running on fumes."
        case 0.5 ..< 0.8: return "Keep it moving."
        case 0.8 ... 1.0: return "Almost there."
        case 1.0 ..< 1.2: return "Over. Noted."
        default: return "That's a surplus."
        }
    }

    // MARK: - Meals List

    private var mealsListSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            // Extra logs aren't part of the plan, so they stay out of both numbers.
            let planned = viewModel.todayMeals.filter { !$0.isUnplannedLog }
            let eaten = planned.count(where: { $0.status == .eaten })
            TideSectionLabel(title: "Today's meals", trailing: "\(eaten)/\(planned.count) done")

            if viewModel.todayMeals.isEmpty {
                if let plan = viewModel.weeklyPlan,
                   Calendar.current.startOfDay(for: plan.startDate) > Calendar.current.startOfDay(for: Date())
                {
                    stalePlanState(plan: plan)
                } else {
                    emptyMealsState
                }
            } else {
                SwipeDeleteList(
                    items: viewModel.todayMeals,
                    rowGap: Tide.s3,
                    swipe: { meal in
                        meal.status == .eaten
                            ? .init(label: meal.isUnplannedLog ? "Delete" : "Not eaten") { undoMeal(meal) }
                            : nil
                    }
                ) { meal in
                    PlannedMealCardView(
                        meal: meal,
                        onOpen: { detailMeal = meal },
                        onMarkEaten: {
                            // Smart default: if the tap lands within ±15 min
                            // of the planned scheduled time, save silently —
                            // the common case on a normal day. Outside that
                            // window we present MarkEatenSheet so the user
                            // can pick the actual eat-time (and optionally
                            // a meal-feel chip or substitute).
                            if PlannedMealTimingMatcher.isNearScheduled(meal: meal, now: Date()) {
                                commitMarkEaten(meal: meal, at: Date(), feel: nil, satiety: nil, substitute: nil)
                            } else {
                                markEatenMeal = meal
                            }
                        },
                        onMarkSkipped: {
                            guard viewModel.markMealSkipped(
                                meal,
                                modelContext: modelContext,
                                notifications: services.notifications
                            )
                            else {
                                toast = ToastData(message: "Couldn't skip \(meal.mealName). Try again.", style: .error)
                                return
                            }
                            // Fire-and-forget AI redistribution. UX
                            // stays snappy; banner appears when the call
                            // returns (sub-second on Haiku, ~2s on retry)
                            // and only when macros were really moved.
                            Task {
                                let recovery = viewModel.todayRecovery?.score
                                let sleep = viewModel.todaySleep?.totalHours
                                let strain = viewModel.todayRecovery.flatMap { _ in nil as Double? }
                                await viewModel.redistributeSkippedMacros(
                                    meal,
                                    modelContext: modelContext,
                                    apiClient: services.apiClient,
                                    recoveryScore: recovery,
                                    sleepHours: sleep,
                                    strain: strain,
                                    dayType: "unknown"
                                )
                            }
                        },
                        onUndo: { undoMeal(meal) },
                        onSavePreset: { beginSavePreset(meal) },
                        onReviewTap: { feedbackMeal = meal },
                        needsReview: meal.status == .eaten
                            && !EatenMealRecorder.isSupplementDose(meal)
                            && !(viewModel.feedbackPresence[meal.id] ?? false)
                    )
                    .matchedTransitionSource(id: meal.id, in: mealZoom)
                }
            }
        }
    }

    /// Banner shown right after an AI skip-redistribution lands. One sentence
    /// of reasoning + a dismiss button. Cleared by the user; not auto-hidden
    /// so they have time to read it.
    private func redistributionBanner(_ text: String) -> some View {
        FuelBanner(
            icon: "sparkles",
            tint: Tide.water,
            title: "Macros redistributed",
            message: text,
            onDismiss: {
                viewModel.lastRedistributionBanner = nil
                HapticManager.lightImpact()
            }
        )
    }

    private var emptyMealsState: some View {
        FuelEmptyState(
            icon: "tray",
            title: "No meals planned today.",
            message: "Generate a weekly plan or log meals manually."
        )
    }

    /// Shown when a `WeeklyMealPlan` exists but its `startDate` is in the
    /// future — typically because it was generated by a pre-2026-05-12
    /// version of `MealPlanGeneratorService` that anchored plans to the
    /// next Monday. We surface the actual range and offer a regenerate
    /// path; we don't mutate the existing plan silently.
    private func stalePlanState(plan: WeeklyMealPlan) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        let startStr = formatter.string(from: plan.startDate)
        let endStr = formatter.string(from: plan.endDate)

        return FuelEmptyState(
            icon: "calendar.badge.clock",
            title: "Your plan starts \(startStr).",
            message: "Covers \(startStr) – \(endStr). Regenerate to anchor it to today."
        ) {
            Button {
                HapticManager.lightImpact()
                viewModel.generatePlan(
                    modelContext: modelContext,
                    whoop: services.whoop,
                    apiClient: services.apiClient,
                    notifications: services.notifications,
                    trainingEngine: services.trainingEngine,
                    healthKit: services.healthKit
                )
            } label: {
                Text(viewModel.isGeneratingPlan ? "Regenerating…" : "Regenerate for Today")
            }
            .buttonStyle(.tidePrimary)
            .disabled(viewModel.isGeneratingPlan)
        }
    }

    // MARK: - Mark Eaten Commit

    /// Sheet's onCommit handler. Routes the user-chosen time into the
    /// existing `markMealEaten(at:)` flow and, when a meal-feel chip or
    /// substitute was provided, persists a `MealFeedback` row.
    /// When a substitute is present, the planned meal's macros are
    /// zeroed (the user didn't eat the planned dish) and the substitute
    /// kcal estimate, if any, replaces them.
    private func commitMarkEaten(
        meal: PlannedMeal,
        at eatTime: Date,
        feel: MealFeel?,
        satiety: MealSatiety?,
        substitute: MarkEatenSheet.Substitute?
    ) {
        guard let substitute else {
            // Pantry decrement, feedback row, shift and rebalance all happen
            // inside the shared service.
            if viewModel.markMealEaten(
                meal, at: eatTime, modelContext: modelContext,
                notifications: services.notifications, feel: feel, satiety: satiety
            ) {
                viewModel.refreshFeedbackPresence(modelContext: modelContext)
            } else {
                toast = ToastData(message: "Couldn't save \(meal.mealName). Try again.", style: .error)
            }
            return
        }
        // Substitute → parse "what you ate" into real foods + DB macros via the
        // NL pipeline and REPLACE the meal's foods/macros (same as the meal
        // detail screen). The planned dish is remembered for Undo. No MealLog
        // (day totals sum PlannedMeal → double-count).
        Task { await resolveSubstitute(
            meal: meal,
            at: eatTime,
            note: substitute.note,
            usedPantry: substitute.usedPantry,
            feel: feel,
            satiety: satiety
        ) }
    }

    @MainActor
    private func resolveSubstitute(
        meal: PlannedMeal,
        at eatTime: Date,
        note: String,
        usedPantry: Bool,
        feel: MealFeel?,
        satiety: MealSatiety?
    ) async {
        let nl = NaturalLanguageLoggingService(apiClient: services.apiClient)
        do {
            let items = try await nl.parseNaturalLanguage(note)
            guard !items.isEmpty else {
                toast = ToastData(
                    message: "Couldn't recognize any food in \"\(note)\". Edit it and try again.",
                    style: .error
                )
                return
            }
            let foods = items.map {
                PlannedFood(
                    name: $0.name, quantityGrams: $0.quantityGrams,
                    calories: $0.calories, proteinG: $0.proteinG,
                    carbsG: $0.carbsG, fatG: $0.fatG
                )
            }
            if viewModel.markMealEaten(
                meal, at: eatTime, modelContext: modelContext,
                notifications: services.notifications, feel: feel, satiety: satiety,
                replacingWith: foods, substituteNote: note,
                pantry: usedPantry ? .foods : .none
            ) {
                viewModel.refreshFeedbackPresence(modelContext: modelContext)
            } else {
                toast = ToastData(message: "Couldn't save \(meal.mealName). Try again.", style: .error)
            }
        } catch {
            // Parse failed — the meal stays planned so the user can retry.
            if let blocker = AIBlocker(error) {
                substituteBlocker = blocker
                return
            }
            toast = ToastData(
                message: "Couldn't read that: \(AIBlocker.message(for: error)). Your meal is unchanged.",
                style: .error
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NutritionTodayView(
            viewModel: NutritionTabViewModel()
        )
    }
    .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
