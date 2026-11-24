//
// DailyNutritionSummaryView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Charts
import SwiftData
import SwiftUI

// MARK: - DailyNutritionSummaryView

// Native nutrition summary with recovery-adjusted targets, macro rings, hydration tracker,
// calorie balance, meal timing, and AI coaching.
// Per MODULE_DASHBOARD.md Section 4.3 — Calorie hero, macro bars, meals, trend chart, AI insight.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct DailyNutritionSummaryView: View {
    var fuelData: FuelQuadrantData?

    @State
    private var showMealLogging = false
    /// Today's real PlannedMeals (active plan or unbound) as display rows.
    @State
    private var meals: [NutritionMealEntry] = []
    /// Last 7 days of eaten-meal totals (oldest first).
    @State
    private var calorieTrend: [DailyEatenTotals] = []

    @Environment(\.modelContext)
    private var modelContext

    /// Real data from FuelQuadrantData when connected, fallback to empty state
    private var caloriesConsumed: Int {
        fuelData?.caloriesConsumed ?? 0
    }

    private var calorieTarget: Int {
        fuelData?.calorieTarget ?? 2400
    }

    private var proteinGrams: Int {
        fuelData?.proteinGrams ?? 0
    }

    private var proteinTarget: Int {
        fuelData?.proteinTarget ?? 180
    }

    private var carbsGrams: Int {
        fuelData?.carbsGrams ?? 0
    }

    private var carbsTarget: Int {
        fuelData?.carbsTarget ?? 280
    }

    private var fatGrams: Int {
        fuelData?.fatGrams ?? 0
    }

    private var fatTarget: Int {
        fuelData?.fatTarget ?? 80
    }

    private var isConnected: Bool {
        fuelData?.isConnected ?? false
    }

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// In, out and the balance side by side; stacked at accessibility sizes.
    private var balanceLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s2))
    }

    // MARK: - Computed

    private var calorieProgress: Double {
        guard calorieTarget > 0 else {
            return 0
        }
        return Double(caloriesConsumed) / Double(calorieTarget)
    }

    private var calorieQuip: String {
        let ratio = calorieProgress
        let remaining = calorieTarget - caloriesConsumed

        switch ratio {
        case ..<0.5: return "You running on fumes?"
        case 0.5 ..< 0.8: return "Still got room for \(remaining) kcal."
        case 0.8 ... 1.0: return "On track. Don't blow it at dinner."
        case 1.0 ..< 1.2: return "Over by \(caloriesConsumed - calorieTarget). Noted."
        default: return "That's a surplus, not a strategy."
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Today's targets exist before the first meal, so the page always
            // shows them; with nothing logged a "log your first meal" card
            // leads instead of replacing the whole page.
            VStack(spacing: Tide.s4) {
                if (fuelData?.mealsLogged ?? 0) == 0 {
                    emptyStateSection
                }
                nutritionModeBanner
                calorieHeroSection
                calorieBalanceSection
                hydrationSection
                mealTimingSection
                mealsSection
                calorieTrendSection
                if isConnected {
                    aiCoachingCard

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
            }
            // Full width: without it the scroll view hugs narrow content.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .tidePage()
        .fuelBottomBar { logMealBar }
        .navigationTitle("Fuel")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            loadMealData()
        }
        .task {
            loadMealData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoNutritionLogged)) { _ in
            loadMealData()
        }
        .sheet(isPresented: $showMealLogging) {
            MealLoggingView()
        }
    }

    // MARK: - Nutrition Mode Banner (Task 1)

    @ViewBuilder
    private var nutritionModeBanner: some View {
        if let targets = fuelData?.adjustedTargets, targets.mode != .standard {
            FuelBanner(
                icon: modeBannerIcon(targets.mode),
                tint: modeBannerColor(targets.mode),
                title: modeBannerTitle(targets.mode),
                message: targets.modeExplanation
            )
        }
    }

    private func modeBannerIcon(_ mode: NutritionMode) -> String {
        switch mode {
        case .repair: "cross.circle.fill"
        case .fuel: "bolt.fill"
        case .rest: "bed.double.fill"
        case .standard: "checkmark.circle.fill"
        }
    }

    private func modeBannerColor(_ mode: NutritionMode) -> Color {
        switch mode {
        case .repair: Tide.danger
        case .fuel: Tide.good
        case .rest: Tide.water
        case .standard: Tide.text2
        }
    }

    private func modeBannerTitle(_ mode: NutritionMode) -> String {
        switch mode {
        case .repair: "Repair mode"
        case .fuel: "Fuel mode"
        case .rest: "Rest day"
        case .standard: "Standard"
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        // The button for it is the bar at the bottom of the page.
        FuelEmptyState(
            icon: "fork.knife",
            title: "Nothing logged yet",
            message: "Log your first meal. The numbers below start moving."
        )
    }

    /// The one action of this page, in the thumb zone.
    private var logMealBar: some View {
        Button {
            showMealLogging = true
            HapticManager.lightImpact()
        } label: {
            Label("Log a meal", systemImage: "plus")
        }
        .buttonStyle(.tidePrimary)
        .accessibilityIdentifier("nutritionSummary.logMeal")
    }

    // MARK: - Calorie Hero Section

    /// Calories as the one big number, the three macros under it, and what is
    /// left of each: the same figures as the Fuel card on Today.
    private var calorieHeroSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(
                title: "Calories",
                trailing: FuelCalorieHero.remaining(consumed: caloriesConsumed, target: calorieTarget)
            )

            VStack(alignment: .leading, spacing: Tide.s2) {
                FuelCalorieHero(consumed: caloriesConsumed, target: calorieTarget)

                // Show base vs adjusted if different
                if let targets = fuelData?.adjustedTargets,
                   targets.baseCalorieTarget != targets.calorieTarget
                {
                    Text("Base: \(targets.baseCalorieTarget) kcal")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .strikethrough()
                }

                // Drill sergeant quip
                Text(calorieQuip)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }

            FuelMacroColumns(
                protein: (proteinGrams, proteinTarget),
                carbs: (carbsGrams, carbsTarget),
                fat: (fatGrams, fatTarget)
            )

            // Remaining macro messages
            VStack(alignment: .leading, spacing: Tide.s1) {
                if let protMsg = NutritionEngine.remainingText(macroName: "Protein", current: proteinGrams, target: proteinTarget) {
                    remainingMacroLabel(protMsg, color: statusColor(fuelData?.proteinStatus ?? .onTrack))
                }
                if let carbMsg = NutritionEngine.remainingText(macroName: "Carbs", current: carbsGrams, target: carbsTarget) {
                    remainingMacroLabel(carbMsg, color: statusColor(fuelData?.carbsStatus ?? .onTrack))
                }
                if let fatMsg = NutritionEngine.remainingText(macroName: "Fat", current: fatGrams, target: fatTarget) {
                    remainingMacroLabel(fatMsg, color: statusColor(fuelData?.fatStatus ?? .onTrack))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tideCard()
    }

    private func remainingMacroLabel(_ text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
            Circle()
                .fill(color)
                .frame(width: Tide.s2, height: Tide.s2)
                .accessibilityHidden(true)
            Text(text)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusColor(_ status: NutritionEngine.MacroStatus) -> Color {
        switch status {
        case .onTrack: Tide.good
        case .behind: Tide.warn
        case .over: Tide.danger
        }
    }

    // MARK: - Calorie Balance Section (Task 5)

    @ViewBuilder
    private var calorieBalanceSection: some View {
        if let active = fuelData?.activeCaloriesBurned, caloriesConsumed > 0 {
            let balance = NutritionEngine.calorieBalance(
                caloriesConsumed: caloriesConsumed,
                activeCalories: active,
                bmr: fuelData?.estimatedBMR,
                isTrainingDay: true,
                goal: .maintain
            )

            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Energy balance")

                balanceLayout {
                    balanceFigure("\(balance.caloriesIn)", label: "In")
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .frame(height: Tide.numeralS)
                            .accessibilityHidden(true)
                    }
                    balanceFigure("\(balance.caloriesOut)", label: "Out")
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(balance.balanceText)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(balance.isHealthy ? Tide.good : Tide.warn)
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                        Text("Balance").tideLabel(Tide.text3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tideCard()
        }
    }

    private func balanceFigure(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            TideNumber(value, size: Tide.numeralS, relativeTo: .headline)
            Text(label).tideLabel(Tide.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hydration Section (Task 4)

    private var hydrationSection: some View {
        // Saved water (WaterStore) — one source for this screen, Nutrition
        // Today and the Dashboard Fuel tile.
        WaterCardView(targetMl: fuelData?.hydrationTargetMl)
    }

    // MARK: - Meal Timing Section (Task 3)

    @ViewBuilder
    private var mealTimingSection: some View {
        let suggestions = fuelData?.mealTimingSuggestions ?? []
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Meal timing")

                ForEach(Array(suggestions.prefix(3).enumerated()), id: \.element.text) { _, suggestion in
                    HStack(alignment: .top, spacing: Tide.s3) {
                        Image(systemName: suggestion.icon)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(suggestion.priority == 0 ? Tide.warn : mood.accent)
                            .frame(width: Tide.icon, alignment: .leading)
                            .accessibilityHidden(true)

                        Text(suggestion.text)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tideCard()
        }
    }

    // MARK: - Meals Section

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Meals")

            if meals.isEmpty {
                Text("No meals on the board today.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 0) {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    mealRow(meal)
                    if index < meals.count - 1 {
                        Divider().overlay(Tide.hairline)
                    }
                }
            }
        }
        .tideCard()
    }

    private func mealRow(_ meal: NutritionMealEntry) -> some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: Tide.s3) {
            // The meal's own symbol, tinted by how it went.
            TideIconTile(
                systemName: FuelMealStyle.icon(forName: meal.type),
                tint: meal.statusColor,
                size: Tide.hit - Tide.s2
            )

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(meal.type)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)

                Text(meal.time)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .monospacedDigit()

                if !meal.items.isEmpty {
                    Text(meal.items.joined(separator: ", "))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                }
            }

            Spacer(minLength: Tide.s2)

            VStack(alignment: .trailing, spacing: Tide.s1) {
                if let calories = meal.calories {
                    TideNumber("\(calories)", unit: "kcal", size: Tide.numeralS, relativeTo: .headline)
                } else {
                    Text("--").font(Tide.body).foregroundStyle(Tide.text3)
                }
                if meal.status != .planned {
                    FuelPill(
                        text: meal.status == .logged ? "Eaten" : "Skipped",
                        color: meal.statusColor
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: Tide.hit + Tide.s3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Calorie Trend Chart

    private var calorieTrendSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Calorie trend", trailing: "7 days")

            if calorieTrend.contains(where: \.hasData) {
                trendChart
            } else {
                Text("Nothing logged this week. Log a meal and the chart starts.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tideCard()
    }

    /// Only days with eaten meals get a bar; empty days leave a gap on the
    /// full 7-day axis instead of a fake 0 or a made-up value.
    private var trendChart: some View {
        Chart {
            ForEach(calorieTrend.filter(\.hasData)) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(point.calories > calorieTarget ? Tide.danger : mood.accent)
                // Today is the bar to read; the days before sit back.
                .opacity(Calendar.current.isDateInToday(point.date) ? 1 : 0.55)
                .cornerRadius(Tide.s1)
            }

            RuleMark(y: .value("Target", calorieTarget))
                .foregroundStyle(Tide.text3)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading, spacing: Tide.hair) {
                    Text("Target")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
        }
        .accessibilityLabel("Calories eaten per day over the last 7 days")
        .chartXScale(domain: trendDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(dayOfWeekAbbrev(date))
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Tide.hairline)
                AxisValueLabel()
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
            }
        }
        .frame(height: Tide.dialSheet + Tide.s10)
        // Axis labels stop growing at xxxLarge, or the seven day names run into each other.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Full 7-day window (start of first day → end of today) so empty days
    /// still occupy their slot on the axis.
    private var trendDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let first = calorieTrend.first?.date ?? cal.startOfDay(for: Date())
        let last = calorieTrend.last?.date ?? first
        let end = cal.date(byAdding: .day, value: 1, to: last) ?? last
        return first ... end
    }

    // MARK: - Data

    private func loadMealData() {
        meals = NutritionMealEntry.entries(from: Self.todayMeals(in: modelContext))
        calorieTrend = EatenNutritionHistory.dailyTotals(in: modelContext)
    }

    /// Today's PlannedMeals — active plan or unbound manual logs, the same
    /// filter the Dashboard Fuel card and Nutrition Today use.
    private static func todayMeals(in context: ModelContext) -> [PlannedMeal] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= todayStart && meal.dayDate < tomorrowStart
            },
            sortBy: [SortDescriptor(\.mealNumber)]
        )
        return ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.mealPlan?.isActive == true || $0.mealPlan == nil }
    }

    // MARK: - AI Coaching Card (Task 6)

    private var aiCoachingCard: some View {
        let message = fuelData?.coachingMessage ?? NutritionEngine.coachingMessage(
            proteinCurrent: proteinGrams, proteinTarget: proteinTarget,
            carbsCurrent: carbsGrams, carbsTarget: carbsTarget,
            fatCurrent: fatGrams, fatTarget: fatTarget,
            caloriesCurrent: caloriesConsumed, calorieTarget: calorieTarget,
            isTrainingDay: true, recoveryZone: nil, mealsLogged: fuelData?.mealsLogged ?? 0
        )

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: Date())

        return VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s3) {
                TideIconTile(systemName: "brain.head.profile", size: Tide.hit - Tide.s2)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Coach").tideLabel()
                    Text("Updated today at \(timeString)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                Spacer(minLength: 0)
            }

            Text(message)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tideCard()
    }

    // MARK: - Helpers

    private func dayOfWeekAbbrev(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).prefix(2).uppercased()
    }
}

// MARK: - NutritionMealEntry

struct NutritionMealEntry: Identifiable {
    let id: UUID
    let type: String
    let time: String
    let calories: Int?
    let items: [String]
    let status: NutritionMealStatus

    var statusIcon: String {
        switch status {
        case .logged: "checkmark.circle.fill"
        case .planned: "circle"
        case .skipped: "xmark.circle.fill"
        }
    }

    var statusColor: Color {
        switch status {
        case .logged: Tide.good
        case .planned: Tide.text3
        case .skipped: Tide.danger
        }
    }
}

extension NutritionMealEntry {
    /// Display rows for today's real PlannedMeals, in eating order
    /// (scheduled time, then meal number). Eaten meals show the actual eat
    /// time; skipped meals show no kcal.
    static func entries(from meals: [PlannedMeal]) -> [NutritionMealEntry] {
        meals
            .sorted { lhs, rhs in
                lhs.scheduledTime != rhs.scheduledTime
                    ? lhs.scheduledTime < rhs.scheduledTime
                    : lhs.mealNumber < rhs.mealNumber
            }
            .map { meal in
                let status: NutritionMealStatus = switch meal.status {
                case .eaten: .logged
                case .skipped: .skipped
                case .planned,
                     .modified: .planned
                }
                let time = if status == .logged, let eatenAt = meal.actualEatenAt {
                    TempoDateFormatters.timeOnly.string(from: eatenAt)
                } else {
                    meal.scheduledTime
                }
                return NutritionMealEntry(
                    id: meal.id,
                    type: meal.mealName,
                    time: time,
                    calories: status == .skipped ? nil : Int(meal.totalCalories.rounded()),
                    items: meal.foods.map(\.name),
                    status: status
                )
            }
    }
}

// MARK: - NutritionMealStatus

enum NutritionMealStatus {
    case logged
    case planned
    case skipped
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DailyNutritionSummaryView(fuelData: {
            var data = FuelQuadrantData(
                caloriesConsumed: 1820, calorieTarget: 2400,
                proteinGrams: 142, proteinTarget: 180,
                carbsGrams: 195, carbsTarget: 280,
                fatGrams: 58, fatTarget: 80,
                mealsLogged: 3, mealsPlanned: 4,
                isConnected: true, lastSync: Date()
            )
            data.hydrationMl = 1250
            data.activeCaloriesBurned = 320
            data.estimatedBMR = 1800
            data.adjustedTargets = NutritionEngine.adjustedTargets(
                baseCalories: 2400, baseProtein: 180, baseCarbs: 280, baseFat: 80,
                recoveryZone: .red, currentStrain: 8.0,
                isTrainingDay: true, isRestDay: false
            )
            data.coachingMessage = NutritionEngine.coachingMessage(
                proteinCurrent: 142, proteinTarget: 207,
                carbsCurrent: 195, carbsTarget: 280,
                fatCurrent: 58, fatTarget: 80,
                caloriesCurrent: 1820, calorieTarget: 2640,
                isTrainingDay: true, recoveryZone: .red, mealsLogged: 3
            )
            data.mealTimingSuggestions = NutritionEngine.mealTimingSuggestions(
                workoutName: "Push Day", workoutStatus: .planned, wakeTimeMinutes: 420
            )
            return data
        }())
    }
}
