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

    /// When set, presents `MarkEatenSheet` for this meal. Combines the
    /// backward-fill time scrubber and the meal-feel chip. Replaces the
    /// previous "tap = commits at .now" behavior — every Mark Eaten tap
    /// now opens this sheet first.
    @State
    private var markEatenMeal: PlannedMeal?

    // Macro colors per MODULE_DASHBOARD.md
    private let proteinColor = Color.tempoMacroProtein
    private let carbsColor = Color.tempoMacroCarbs
    private let fatColor = Color.tempoMacroFat

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                if let banner = viewModel.lastRedistributionBanner {
                    redistributionBanner(banner)
                }
                macroRingsSection
                UseUpSoonCard(viewModel: viewModel)
                calorieProgressSection
                mealsListSection

                // AI disclaimer
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("AI-generated guidance. Not medical or dietetic advice. Consult a professional for personalized plans.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .padding(.vertical, TempoSpacing.sm)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe)
        }
        // Meal logging now lives solely on the Log tab — the Today page's
        // floating "Log a Meal" FAB was removed (redundant entry point).
        .task {
            // Refresh pantry + recipe suggestions so UseUpSoonCard has FIFO-ranked
            // candidates without requiring a visit to the Recipes tab first.
            viewModel.reloadPantry()
            viewModel.refreshRecipeSuggestions()
        }
        .sheet(item: $feedbackMeal, onDismiss: {
            viewModel.refreshFeedbackPresence(modelContext: modelContext)
        }) { meal in
            MealFeedbackSheet(meal: meal)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $markEatenMeal) { meal in
            MarkEatenSheet(meal: meal) { eatTime, feel, substitute in
                commitMarkEaten(meal: meal, at: eatTime, feel: feel, substitute: substitute)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Macro Rings

    private var macroRingsSection: some View {
        HStack(spacing: TempoSpacing.xl) {
            macroRing(
                name: "Protein",
                current: viewModel.todayProteinConsumed,
                target: viewModel.todayProteinTarget,
                color: proteinColor
            )
            macroRing(
                name: "Carbs",
                current: viewModel.todayCarbsConsumed,
                target: viewModel.todayCarbsTarget,
                color: carbsColor
            )
            macroRing(
                name: "Fat",
                current: viewModel.todayFatConsumed,
                target: viewModel.todayFatTarget,
                color: fatColor
            )
        }
        .tempoCard()
    }

    private func macroRing(name: String, current: Int, target: Int, color: Color) -> some View {
        let progress = target > 0 ? Double(current) / Double(target) : 0

        return VStack(spacing: TempoSpacing.xs) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 6, lineCap: .round))

                Circle()
                    .trim(from: 0, to: min(progress, 1.0))
                    .stroke(
                        progress > 1.0 ? Color.tempoError : color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(TempoAnimation.springData, value: progress)

                Text("\(current)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // Cap the text to the circle's inner area minus the stroke
                    // so 3+ digit values shrink instead of clipping over the
                    // donut edge.
                    .frame(width: 52)
            }
            .frame(width: 64, height: 64)

            Text(name)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
                .lineLimit(1)

            Text("\(current)/\(target)g")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.tempoTextTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Worst-case "999/999g" needs to fit a ~64pt column without
                // overflowing the adjacent ring; cap width so the scale
                // factor kicks in before the text reaches the next column.
                .frame(maxWidth: 80)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Calorie Progress

    private var calorieProgressSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack {
                Text("CALORIES")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                Spacer()

                Text(calorieQuip)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .italic()
            }

            HStack(spacing: TempoSpacing.sm) {
                Text("\(viewModel.todayCaloriesConsumed)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("/ \(viewModel.todayCalorieTarget) kcal")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.tempoViolet.opacity(0.15))
                        .frame(height: 10)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.tempoViolet.opacity(0.6), Color.tempoViolet],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(viewModel.calorieProgress, 1.0), height: 10)
                        .animation(TempoAnimation.springData, value: viewModel.calorieProgress)
                }
            }
            .frame(height: 10)

            let remaining = viewModel.todayCalorieTarget - viewModel.todayCaloriesConsumed
            if remaining > 0 {
                Text("\(remaining) kcal remaining")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            } else {
                Text("\(abs(remaining)) kcal over target")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoError)
            }
        }
        .tempoCard()
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack {
                Text("TODAY'S MEALS")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                Spacer()

                let eaten = viewModel.todayMeals.count(where: { $0.status == .eaten })
                Text("\(eaten)/\(viewModel.todayMeals.count) done")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            if viewModel.todayMeals.isEmpty {
                if let plan = viewModel.weeklyPlan,
                   Calendar.current.startOfDay(for: plan.startDate) > Calendar.current.startOfDay(for: Date())
                {
                    stalePlanState(plan: plan)
                } else {
                    emptyMealsState
                }
            } else {
                ForEach(viewModel.todayMeals, id: \.id) { meal in
                    PlannedMealCardView(
                        meal: meal,
                        onMarkEaten: {
                            // Smart default: if the tap lands within ±15 min
                            // of the planned scheduled time, save silently —
                            // the common case on a normal day. Outside that
                            // window we present MarkEatenSheet so the user
                            // can pick the actual eat-time (and optionally
                            // a meal-feel chip or substitute).
                            if PlannedMealTimingMatcher.isNearScheduled(meal: meal, now: Date()) {
                                viewModel.markMealEaten(
                                    meal,
                                    modelContext: modelContext,
                                    notifications: services.notifications
                                )
                                PantryDecrementService.decrement(for: meal, modelContext: modelContext)
                            } else {
                                markEatenMeal = meal
                            }
                        },
                        onMarkSkipped: {
                            viewModel.markMealSkipped(
                                meal,
                                modelContext: modelContext,
                                notifications: services.notifications
                            )
                            // Fire-and-forget AI redistribution. UX
                            // stays snappy; banner appears when the call
                            // returns (sub-second on Haiku, ~2s on retry).
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
                        onReviewTap: { feedbackMeal = meal },
                        needsReview: meal.status == .eaten
                            && !(viewModel.feedbackPresence[meal.id] ?? false)
                    )
                }
            }
        }
    }

    /// Banner shown right after an AI skip-redistribution lands. One sentence
    /// of reasoning + a dismiss button. Cleared by the user; not auto-hidden
    /// so they have time to read it.
    private func redistributionBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.tempoElectric)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Macros redistributed")
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(text)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                viewModel.lastRedistributionBanner = nil
                HapticManager.lightImpact()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoElectric.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    private var emptyMealsState: some View {
        VStack(spacing: TempoSpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("No meals planned today.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            Text("Generate a weekly plan or log meals manually.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxl)
        .tempoCard()
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

        return VStack(spacing: TempoSpacing.md) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundStyle(Color.tempoAmber)

            Text("Your plan starts \(startStr).")
                .font(.tempoBody)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)

            Text("Covers \(startStr) – \(endStr). Regenerate to anchor it to today.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                HapticManager.lightImpact()
                viewModel.generatePlan(
                    modelContext: modelContext,
                    whoop: services.whoop,
                    apiClient: services.apiClient,
                    notifications: services.notifications
                )
            } label: {
                Text(viewModel.isGeneratingPlan ? "Regenerating…" : "Regenerate for Today")
                    .font(.tempoCallout)
            }
            .buttonStyle(.tempoPrimary)
            .disabled(viewModel.isGeneratingPlan)
            .padding(.top, TempoSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxl)
        .padding(.horizontal, TempoSpacing.lg)
        .tempoCard()
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
        substitute: MarkEatenSheet.Substitute?
    ) {
        if let substitute {
            meal.totalCalories = substitute.calories ?? 0
            // No per-macro estimate — only the calorie field exists in
            // the quick-swap lane. Protein/carbs/fat are unknown.
            meal.totalProtein = 0
            meal.totalCarbs = 0
            meal.totalFat = 0
        }
        viewModel.markMealEaten(
            meal,
            at: eatTime,
            modelContext: modelContext,
            notifications: services.notifications
        )
        // Pantry decrement runs only when the user actually ate the
        // planned dish. A substitute means the planned ingredients are
        // still on the shelf.
        if substitute == nil {
            PantryDecrementService.decrement(for: meal, modelContext: modelContext)
        }
        if feel != nil || substitute != nil {
            let feedback = MealFeedback(
                plannedMeal: meal,
                mealFeel: feel,
                substituteNote: substitute?.note,
                substituteCalories: substitute?.calories
            )
            modelContext.insert(feedback)
            try? modelContext.save()
        }
        viewModel.refreshFeedbackPresence(modelContext: modelContext)
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
