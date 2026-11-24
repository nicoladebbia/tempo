//
// NutritionCoachView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Nutrition Coach View

// AI coaching section with daily message, meal suggestions, and recovery-aware guidance.
// Four glass cards on the Fuel page's field: briefing, suggestion, recovery, feedback.

struct NutritionCoachView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// AI state for the three coach sections (daily briefing, recovery
    /// guidance, meal feedback). Lives here, not on NutritionTabViewModel —
    /// the fixed-text templates below remain the offline / AI-off fallback.
    @State
    private var insights = NutritionCoachInsightsModel()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                dailyCoachingCard
                mealSuggestionSection
                recoveryGuidanceCard
                recentMealFeedback

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
            // Pin the content to the screen width so it only scrolls up and down.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task {
            viewModel.loadRecoveryData(whoop: services.whoop)
        }
        .task(id: insightTrigger) {
            await loadInsights()
        }
    }

    // MARK: - AI insights

    /// Re-runs the insight load when the inputs the AI needs arrive (targets
    /// computed, Whoop recovery loaded, a new meal eaten). Each section is
    /// cached per day, so re-runs only hit the network for what's missing.
    private var insightTrigger: String {
        let eatenIDs = eatenMeals.map(\.id.uuidString).joined(separator: ",")
        let recovery = viewModel.recoveryScore.map { "\(Int($0))" } ?? "none"
        return "\(viewModel.todayCalorieTarget)|\(recovery)|\(eatenIDs)"
    }

    private var eatenMeals: [PlannedMeal] {
        viewModel.todayMeals.filter { $0.status == .eaten && !EatenMealRecorder.isSupplementDose($0) }
    }

    private var coachProvider: NutritionCoachService {
        NutritionCoachService(apiClient: services.apiClient)
    }

    private var isOnline: Bool {
        services.networkMonitor.isConnected
    }

    private func dayContext() -> CoachDayContext {
        let calendar = Calendar.current
        let today = Date()
        let dayTypes = viewModel.weeklyPlan?.dayTypes ?? [:]
        let todayType = dayTypes[calendar.component(.weekday, from: today)]
        let tomorrowType = calendar.date(byAdding: .day, value: 1, to: today)
            .flatMap { dayTypes[calendar.component(.weekday, from: $0)] }
        return CoachDayContext(
            eatenMeals: eatenMeals.map(CoachMealSnapshot.init(meal:)),
            caloriesConsumed: Double(viewModel.todayCaloriesConsumed),
            proteinConsumed: Double(viewModel.todayProteinConsumed),
            carbsConsumed: Double(viewModel.todayCarbsConsumed),
            fatConsumed: Double(viewModel.todayFatConsumed),
            calorieTarget: Double(viewModel.todayCalorieTarget),
            proteinTarget: Double(viewModel.todayProteinTarget),
            carbsTarget: Double(viewModel.todayCarbsTarget),
            fatTarget: Double(viewModel.todayFatTarget),
            mealsPlanned: viewModel.todayMeals.count,
            recovery: viewModel.todayRecovery,
            sleep: viewModel.todaySleep,
            trainingToday: todayType?.displayName,
            tomorrowTraining: tomorrowType?.displayName
        )
    }

    private func loadInsights() async {
        insights.restoreFromCache(eatenMealIDs: eatenMeals.map(\.id))
        // No targets yet → the tab hasn't loaded today; asking the AI now
        // would cache a briefing built on zeros for the whole day.
        guard viewModel.todayCalorieTarget > 0 else {
            return
        }
        let day = dayContext()
        let provider = coachProvider
        await insights.loadDailyBriefing(day, provider: provider, isOnline: isOnline)
        await insights.loadRecoveryGuidance(day, provider: provider, isOnline: isOnline)
        await insights.loadMealFeedback(for: day.eatenMeals, day: day, provider: provider, isOnline: isOnline)
    }

    private func refreshDailyBriefing() {
        Task {
            await insights.loadDailyBriefing(dayContext(), provider: coachProvider, isOnline: isOnline, force: true)
        }
    }

    private func refreshRecoveryGuidance() {
        Task {
            await insights.loadRecoveryGuidance(dayContext(), provider: coachProvider, isOnline: isOnline, force: true)
        }
    }

    private func retryMealFeedback() {
        Task {
            let day = dayContext()
            await insights.loadMealFeedback(for: day.eatenMeals, day: day, provider: coachProvider, isOnline: isOnline)
        }
    }

    // MARK: - Shared pieces

    /// Spinner row shared by the AI sections (same pattern as the meal-suggestion card).
    private func insightLoadingRow(_ text: String) -> some View {
        FuelAIState(kind: .working(text), isCard: false)
            .accessibilityElement(children: .combine)
    }

    /// Error line + retry under the fallback template.
    private func insightErrorRow(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: Tide.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Tide.caption)
                .foregroundStyle(Tide.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(Tide.caption)
                .foregroundStyle(Tide.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tide.s2)
            Button("Retry", action: retry)
                .buttonStyle(.plain)
                .font(Tide.bodyStrong)
                .foregroundStyle(mood.accent)
                .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                .contentShape(.rect)
        }
    }

    private func refreshButton(isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .frame(width: Tide.hit, height: Tide.hit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !isOnline)
        .accessibilityLabel("Refresh")
    }

    /// The small tracked title of a card, with its icon.
    private func cardTitle(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: Tide.s2) {
            Image(systemName: icon)
                .font(Tide.bodyStrong)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title).tideLabel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// One small figure in a stat row: label over a condensed number.
    private struct Stat {
        let label: String
        let value: String
        let unit: String
        let color: Color
    }

    /// A row of stats; stacked at accessibility text sizes so nothing truncates.
    private func statRow(_ stats: [Stat]) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return layout {
            ForEach(stats, id: \.label) { stat in
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(stat.label).tideLabel()
                    TideNumber(
                        stat.value,
                        unit: stat.unit.isEmpty ? nil : stat.unit,
                        size: Tide.numeralS,
                        relativeTo: .headline,
                        color: stat.color
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Daily Coaching Card

    private var dailyCoachingCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(spacing: Tide.s2) {
                cardTitle("Daily briefing", icon: "brain.head.profile", tint: mood.accent)
                Spacer(minLength: Tide.s2)
                if !isOnline {
                    FuelPill(text: "Offline", color: Tide.warn)
                }
                Text(todayTimeString)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .monospacedDigit()
                if insights.daily.value != nil {
                    refreshButton(isLoading: insights.daily.isLoading, action: refreshDailyBriefing)
                        .padding(.vertical, -Tide.s3)
                        .padding(.trailing, -Tide.s3)
                }
            }

            if insights.daily.isLoading {
                insightLoadingRow("Reading your day…")
            } else {
                // The briefing is the hero of this page.
                Text(insights.daily.value ?? dailyMessage)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = insights.daily.errorMessage {
                insightErrorRow(error, retry: refreshDailyBriefing)
            }

            // Today's stats summary
            VStack(alignment: .leading, spacing: Tide.s4) {
                FuelCalorieHero(consumed: viewModel.todayCaloriesConsumed, target: viewModel.todayCalorieTarget)
                FuelMacroColumns(
                    protein: (viewModel.todayProteinConsumed, viewModel.todayProteinTarget),
                    carbs: (viewModel.todayCarbsConsumed, viewModel.todayCarbsTarget),
                    fat: (viewModel.todayFatConsumed, viewModel.todayFatTarget)
                )
            }
        }
        .tideCard()
        .animation(Tide.snap, value: insights.daily.isLoading)
    }

    // MARK: - Meal Suggestion

    private var mealSuggestionSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            cardTitle("Meal suggestion", icon: "sparkles", tint: mood.accent)

            if viewModel.isLoadingMealSuggestions {
                insightLoadingRow("Finding meals for your remaining macros…")
            } else if !viewModel.mealSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    ForEach(viewModel.mealSuggestions) { suggestion in
                        suggestionRow(suggestion)
                        if suggestion.id != viewModel.mealSuggestions.last?.id {
                            Divider().overlay(Tide.hairline)
                        }
                    }
                }
            } else if let error = viewModel.mealSuggestionError {
                FuelAIState(
                    kind: .failed(title: "No suggestion this time", message: error),
                    isCard: false
                )
            } else {
                Text("Tap below to get a personalized meal suggestion based on your remaining macros and preferences.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                viewModel.getMealSuggestions(apiClient: services.apiClient)
            } label: {
                HStack(spacing: Tide.s2) {
                    if viewModel.isLoadingMealSuggestions {
                        ProgressView()
                            .tint(Tide.ink)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(viewModel.mealSuggestions.isEmpty ? "Get Meal Suggestion" : "New Suggestion")
                        .multilineTextAlignment(.center)
                }
            }
            .buttonStyle(.tidePrimary)
            .disabled(viewModel.isLoadingMealSuggestions)
        }
        .tideCard()
        .animation(Tide.snap, value: viewModel.isLoadingMealSuggestions)
        .sensoryFeedback(.success, trigger: viewModel.mealSuggestions.count) { old, new in new > old }
    }

    private func suggestionRow(_ suggestion: MealSuggestion) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(suggestion.name)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tide.s2)
                Text(suggestion.prepTime)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }

            Text(suggestion.description)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                TideNumber("\(suggestion.calories)", unit: "kcal", size: Tide.numeralS, relativeTo: .headline)
                FuelMacroInline(protein: suggestion.protein, carbs: suggestion.carbs, fat: suggestion.fat)
            }
        }
    }

    // MARK: - Recovery Guidance

    private var recoveryGuidanceCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(spacing: Tide.s2) {
                cardTitle("Recovery-aware guidance", icon: "heart.circle.fill", tint: recoveryColor)

                Spacer(minLength: Tide.s2)

                if let score = viewModel.recoveryScore {
                    FuelPill(text: "\(Int(score))%", color: recoveryColor)
                }

                if insights.recovery.value != nil {
                    refreshButton(isLoading: insights.recovery.isLoading, action: refreshRecoveryGuidance)
                        .padding(.vertical, -Tide.s3)
                        .padding(.trailing, -Tide.s3)
                }
            }

            // Whoop recovery stats row
            if let recovery = viewModel.todayRecovery {
                statRow(recoveryStats(recovery))
            }

            if insights.recovery.isLoading {
                insightLoadingRow("Building recovery guidance…")
            } else {
                Text(insights.recovery.value?.message ?? recoveryNutritionMessage)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)

                // Recovery nutrition tips
                VStack(alignment: .leading, spacing: Tide.s2) {
                    ForEach(displayedRecoveryTips, id: \.text) { tip in
                        recoveryTip(icon: tip.icon, text: tip.text)
                    }
                }
            }

            if let error = insights.recovery.errorMessage {
                insightErrorRow(error, retry: refreshRecoveryGuidance)
            }
        }
        .tideCard()
        .animation(Tide.snap, value: insights.recovery.isLoading)
    }

    private func recoveryStats(_ recovery: WhoopRecoveryData) -> [Stat] {
        var stats = [
            Stat(
                label: "Recovery",
                value: "\(Int(recovery.score))%",
                unit: viewModel.recoveryZone?.uppercased() ?? "",
                color: recoveryColor
            ),
            Stat(label: "HRV", value: String(format: "%.0f", recovery.hrvRmssd), unit: "ms", color: Tide.text),
            Stat(label: "RHR", value: String(format: "%.0f", recovery.restingHeartRate), unit: "bpm", color: Tide.text),
        ]
        if let sleep = viewModel.todaySleep {
            stats.append(Stat(label: "Sleep", value: String(format: "%.1f", sleep.totalHours), unit: "hrs", color: Tide.text))
        }
        return stats
    }

    private func recoveryTip(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
            Image(systemName: icon)
                .font(Tide.caption)
                .foregroundStyle(mood.accent)
                .frame(width: Tide.s5, alignment: .leading)
                .accessibilityHidden(true)

            Text(text)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Recent Meal Feedback

    private var recentMealFeedback: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            cardTitle("Meal feedback", icon: "chart.bar.fill", tint: mood.accent)

            if eatenMeals.isEmpty {
                Text("No meals logged today. Get moving, soldier.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    ForEach(eatenMeals, id: \.id) { meal in
                        mealFeedbackRow(meal)
                    }
                }

                if let error = eatenMeals.lazy.compactMap({ insights.feedbackState(for: $0.id).errorMessage }).first {
                    insightErrorRow(error, retry: retryMealFeedback)
                }
            }
        }
        .tideCard()
    }

    private func mealFeedbackRow(_ meal: PlannedMeal) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Image(systemName: "checkmark.circle.fill")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.good)
                .frame(width: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(meal.mealName)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)

                let feedback = insights.feedbackState(for: meal.id)
                if feedback.isLoading {
                    insightLoadingRow("Reviewing…")
                } else {
                    Text(feedback.value ?? mealFeedback(for: meal))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Tide.s2)

            TideNumber("\(Int(meal.totalCalories))", unit: "kcal", size: Tide.numeralS, relativeTo: .headline, color: Tide.text2)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Computed

    private var todayTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private var dailyMessage: String {
        let progress = viewModel.calorieProgress
        let proteinRatio = viewModel.todayProteinTarget > 0
            ? Double(viewModel.todayProteinConsumed) / Double(viewModel.todayProteinTarget)
            : 0

        // Recovery-aware opening when Whoop data is available
        let recoveryPrefix = if let zone = viewModel.recoveryZone, let score = viewModel.recoveryScore {
            switch zone {
            case "red":
                "Recovery at \(Int(score))% (RED). Your body is depleted. "
            case "yellow":
                "Recovery at \(Int(score))% (YELLOW). Not fully charged. "
            default:
                "Recovery at \(Int(score))% (GREEN). Body is primed. "
            }
        } else {
            ""
        }

        if viewModel.todayMeals.isEmpty {
            return "\(recoveryPrefix)Day hasn't started. Your body needs fuel to perform. Don't make me repeat myself."
        }

        if progress < 0.3 {
            return "\(recoveryPrefix)You're underfueling. At this rate you'll be running on fumes by afternoon. Fix it."
        }

        if proteinRatio < 0.5, progress > 0.5 {
            return "\(recoveryPrefix)Calories are moving but your protein is lagging behind. Prioritize lean protein in your next meal."
        }

        if progress >= 0.8, progress <= 1.05 {
            return "\(recoveryPrefix)Solid execution today. Macros are tracking well. Keep the discipline."
        }

        if progress > 1.1 {
            return "\(recoveryPrefix)Over target. It happens. Don't spiral. Tomorrow is a clean slate. Hydrate and move on."
        }

        return "\(recoveryPrefix)You're on pace. Stay focused. Every meal is a rep."
    }

    private var recoveryColor: Color {
        guard let zone = viewModel.recoveryZone else {
            return Tide.text3
        }
        switch zone {
        case "green": return Tide.good
        case "yellow": return Tide.warn
        case "red": return Tide.danger
        default: return Tide.text3
        }
    }

    private var recoveryNutritionMessage: String {
        guard let zone = viewModel.recoveryZone, let score = viewModel.recoveryScore else {
            return "Connect Whoop to get recovery-aware nutrition guidance. Your recovery score drives personalized recommendations."
        }

        switch zone {
        case "red":
            return "Recovery is critically low at \(Int(score))%. Your body is in repair mode. Increase protein by 15-20%, prioritize anti-inflammatory foods, and avoid processed sugar and alcohol. Hydration is non-negotiable."
        case "yellow":
            return "Recovery at \(Int(score))% — your body is working hard. Increase protein by 10-15%, focus on nutrient-dense meals, and add anti-inflammatory foods like berries, fatty fish, and turmeric."
        default:
            return "Recovery is strong at \(Int(score))%. You're cleared to push hard. Fuel for performance — high carbs if training today, maintain protein targets, and stay hydrated."
        }
    }

    private struct RecoveryTipData: Hashable {
        let icon: String
        let text: String
    }

    /// AI tips when loaded (uniform icon), otherwise the per-zone template.
    private var displayedRecoveryTips: [RecoveryTipData] {
        if let tips = insights.recovery.value?.tips, !tips.isEmpty {
            return tips.map { RecoveryTipData(icon: "bolt.heart.fill", text: $0) }
        }
        return recoveryTips
    }

    private var recoveryTips: [RecoveryTipData] {
        let zone = viewModel.recoveryZone ?? "none"

        switch zone {
        case "red":
            return [
                RecoveryTipData(icon: "drop.fill", text: "Hydration is critical — aim for 4L+ today. Add electrolytes."),
                RecoveryTipData(icon: "leaf.fill", text: "Anti-inflammatory priority: berries, salmon, turmeric, ginger."),
                RecoveryTipData(icon: "bed.double.fill", text: "Consider lighter training. Your body needs repair, not more stress."),
                RecoveryTipData(icon: "xmark.circle.fill", text: "Avoid alcohol, processed sugar, and fried foods today."),
            ]
        case "yellow":
            return [
                RecoveryTipData(icon: "drop.fill", text: "Prioritize hydration — aim for 3L+ today."),
                RecoveryTipData(icon: "leaf.fill", text: "Anti-inflammatory foods: berries, fish, turmeric."),
                RecoveryTipData(icon: "clock.fill", text: "Eat within 30 min post-workout for optimal recovery."),
            ]
        default:
            return [
                RecoveryTipData(icon: "bolt.fill", text: "Green zone — fuel for performance. High carbs pre-workout."),
                RecoveryTipData(icon: "drop.fill", text: "Stay hydrated — 3L minimum, more if training hard."),
                RecoveryTipData(icon: "clock.fill", text: "Eat within 30 min post-workout for optimal recovery."),
            ]
        }
    }

    private func mealFeedback(for meal: PlannedMeal) -> String {
        let proteinRatio = meal.totalCalories > 0
            ? (meal.totalProtein * 4) / meal.totalCalories
            : 0

        if proteinRatio > 0.35 {
            return "High protein. Good discipline."
        } else if proteinRatio < 0.15 {
            return "Low protein. Add a source next time."
        } else {
            return "Balanced macros. Solid."
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NutritionCoachView(viewModel: NutritionTabViewModel())
    }
    .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
