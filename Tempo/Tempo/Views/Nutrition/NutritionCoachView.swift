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
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct NutritionCoachView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    /// AI state for the three coach sections (daily briefing, recovery
    /// guidance, meal feedback). Lives here, not on NutritionTabViewModel —
    /// the fixed-text templates below remain the offline / AI-off fallback.
    @State
    private var insights = NutritionCoachInsightsModel()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.md) {
                dailyCoachingCard
                mealSuggestionSection
                recoveryGuidanceCard
                recentMealFeedback

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
            // Pin the content to the screen width: a too-wide row used to
            // make the whole page drag sideways.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
        viewModel.todayMeals.filter { $0.status == .eaten }
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
        guard viewModel.todayCalorieTarget > 0 else { return }
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

    /// Spinner row shared by the AI sections (same pattern as the meal-suggestion card).
    private func insightLoadingRow(_ text: String) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            ProgressView()
                .scaleEffect(0.8)
            Text(text)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    /// Error line + retry under the fallback template.
    private func insightErrorRow(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: TempoSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.tempoError)
            Text(message)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoError)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TempoSpacing.xs)
            Button("Retry", action: retry)
                .font(.tempoCaption1.weight(.semibold))
                .foregroundStyle(Color.tempoViolet)
        }
    }

    private func refreshButton(isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !isOnline)
        .accessibilityLabel("Refresh")
    }

    // MARK: - Daily Coaching Card

    private var dailyCoachingCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.tempoViolet)

                Text("DAILY BRIEFING")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                Text(todayTimeString)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)

                if insights.daily.value != nil {
                    refreshButton(isLoading: insights.daily.isLoading, action: refreshDailyBriefing)
                }
            }

            if insights.daily.isLoading {
                insightLoadingRow("Reading your day…")
            } else {
                Text(insights.daily.value ?? dailyMessage)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = insights.daily.errorMessage {
                insightErrorRow(error, retry: refreshDailyBriefing)
            }

            // Today's stats summary
            HStack(spacing: TempoSpacing.lg) {
                coachStat(
                    label: "Eaten",
                    value: "\(viewModel.todayCaloriesConsumed)",
                    unit: "kcal",
                    color: Color.tempoViolet
                )
                coachStat(
                    label: "Target",
                    value: "\(viewModel.todayCalorieTarget)",
                    unit: "kcal",
                    color: Color.tempoTextSecondary
                )
                coachStat(
                    label: "Protein",
                    value: "\(viewModel.todayProteinConsumed)",
                    unit: "/\(viewModel.todayProteinTarget)g",
                    color: Color.tempoMacroProtein
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card.daily")
    }

    private func coachStat(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.tempoTextTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Meal Suggestion

    private var mealSuggestionSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.tempoAmber)

                Text("MEAL SUGGESTION")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if viewModel.isLoadingMealSuggestions {
                HStack(spacing: TempoSpacing.sm) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Finding meals for your remaining macros…")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            } else if !viewModel.mealSuggestions.isEmpty {
                ForEach(viewModel.mealSuggestions) { suggestion in
                    VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                        HStack {
                            Text(suggestion.name)
                                .font(.tempoCallout)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            Text(suggestion.prepTime)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }

                        Text(suggestion.description)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: TempoSpacing.md) {
                            macroLabel("\(suggestion.calories)", "kcal", Color.tempoViolet)
                            macroLabel("\(suggestion.protein)g", "P", Color.tempoMacroProtein)
                            macroLabel("\(suggestion.carbs)g", "C", Color.tempoAmber)
                            macroLabel("\(suggestion.fat)g", "F", Color.tempoElectric)
                        }
                    }
                    .padding(.vertical, TempoSpacing.xs)
                }
            } else if let error = viewModel.mealSuggestionError {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tempoError)
                    Text(error)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }
            } else {
                Text("Tap below to get a personalized meal suggestion based on your remaining macros and preferences.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Button {
                viewModel.getMealSuggestions(apiClient: services.apiClient)
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoadingMealSuggestions {
                        ProgressView()
                            .tint(Color.tempoTextInverse)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14))
                    }
                    Text(viewModel.mealSuggestions.isEmpty ? "Get Meal Suggestion" : "New Suggestion")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.tempoTextInverse)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    viewModel.isLoadingMealSuggestions
                        ? Color.tempoAmber.opacity(0.6)
                        : Color.tempoAmber
                )
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .disabled(viewModel.isLoadingMealSuggestions)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card.suggestion")
    }

    private func macroLabel(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Recovery Guidance

    private var recoveryGuidanceCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(recoveryColor)

                Text("RECOVERY-AWARE GUIDANCE")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                if insights.recovery.value != nil {
                    refreshButton(isLoading: insights.recovery.isLoading, action: refreshRecoveryGuidance)
                }

                if let score = viewModel.recoveryScore {
                    Text("\(Int(score))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(recoveryColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(recoveryColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Whoop recovery stats row
            if let recovery = viewModel.todayRecovery {
                HStack(spacing: TempoSpacing.lg) {
                    coachStat(
                        label: "Recovery",
                        value: "\(Int(recovery.score))%",
                        unit: viewModel.recoveryZone?.uppercased() ?? "",
                        color: recoveryColor
                    )
                    coachStat(
                        label: "HRV",
                        value: String(format: "%.0f", recovery.hrvRmssd),
                        unit: "ms",
                        color: Color.tempoElectric
                    )
                    coachStat(
                        label: "RHR",
                        value: String(format: "%.0f", recovery.restingHeartRate),
                        unit: "bpm",
                        color: Color.tempoTextSecondary
                    )
                    if let sleep = viewModel.todaySleep {
                        coachStat(
                            label: "Sleep",
                            value: String(format: "%.1f", sleep.totalHours),
                            unit: "hrs",
                            color: Color.tempoViolet
                        )
                    }
                }
            }

            if insights.recovery.isLoading {
                insightLoadingRow("Building recovery guidance…")
            } else {
                Text(insights.recovery.value?.message ?? recoveryNutritionMessage)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Recovery nutrition tips
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    ForEach(displayedRecoveryTips, id: \.text) { tip in
                        recoveryTip(icon: tip.icon, text: tip.text)
                    }
                }
            }

            if let error = insights.recovery.errorMessage {
                insightErrorRow(error, retry: refreshRecoveryGuidance)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card.recovery")
    }

    private func recoveryTip(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.tempoViolet)
                .frame(width: 16)

            Text(text)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Recent Meal Feedback

    private var recentMealFeedback: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.tempoElectric)

                Text("MEAL FEEDBACK")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if eatenMeals.isEmpty {
                Text("No meals logged today. Get moving, soldier.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .italic()
            } else {
                ForEach(eatenMeals, id: \.id) { meal in
                    mealFeedbackRow(meal)
                }

                if let error = eatenMeals.lazy.compactMap({ insights.feedbackState(for: $0.id).errorMessage }).first {
                    insightErrorRow(error, retry: retryMealFeedback)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card.feedback")
    }

    private func mealFeedbackRow(_ meal: PlannedMeal) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.tempoSuccess)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealName)
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)

                let feedback = insights.feedbackState(for: meal.id)
                if feedback.isLoading {
                    insightLoadingRow("Reviewing…")
                } else {
                    Text(feedback.value ?? mealFeedback(for: meal))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Text("\(Int(meal.totalCalories)) kcal")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(.vertical, TempoSpacing.xxs)
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
            return .tempoTextTertiary
        }
        switch zone {
        case "green": return .tempoSuccess
        case "yellow": return .tempoWarning
        case "red": return .tempoError
        default: return .tempoTextTertiary
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
