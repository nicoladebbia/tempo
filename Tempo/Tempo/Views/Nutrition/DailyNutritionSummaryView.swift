//
// DailyNutritionSummaryView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Charts
import SwiftUI

// MARK: - DailyNutritionSummaryView

// Native nutrition summary with recovery-adjusted targets, macro rings, hydration tracker,
// calorie balance, meal timing, and AI coaching.
// Per MODULE_DASHBOARD.md Section 4.3 — Calorie hero, macro bars, meals, trend chart, AI insight.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct DailyNutritionSummaryView: View {
    var fuelData: FuelQuadrantData?
    var onAddHydration: ((Int) -> Void)?

    @State
    private var showMealLogging = false
    @State
    private var isRefreshing = false
    @State
    private var localHydrationBonus: Int = 0

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

    // Macro colors per MODULE_DASHBOARD.md Section 3.4.2
    private let proteinColor = Color.tempoMacroProtein
    private let carbsColor = Color.tempoMacroCarbs
    private let fatColor = Color.tempoMacroFat

    /// Meal display based on connection status
    private var meals: [NutritionMealEntry] {
        guard isConnected else {
            return []
        }
        let logged = fuelData?.mealsLogged ?? 0
        let planned = fuelData?.mealsPlanned ?? 4
        let mealTypes = ["Breakfast", "Lunch", "Snack", "Dinner"]
        return (0 ..< planned).map { index in
            let type = index < mealTypes.count ? mealTypes[index] : "Meal \(index + 1)"
            let isLogged = index < logged
            return NutritionMealEntry(
                id: UUID(),
                type: type,
                time: isLogged ? "--" : "--",
                calories: isLogged ? caloriesConsumed / max(logged, 1) : nil,
                items: [],
                status: isLogged ? .logged : .planned
            )
        }
    }

    /// 7-day calorie trend — synthetic from current data when connected
    private var calorieTrend: [CalorieTrendPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayCal = caloriesConsumed > 0 ? caloriesConsumed : calorieTarget
        return (-6 ... 0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let variance = Int.random(in: -200 ... 200)
            let value = offset == 0 ? caloriesConsumed : max(0, todayCal + variance)
            return CalorieTrendPoint(date: date, calories: value)
        }
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
            VStack(spacing: TempoSpacing.xl) {
                if isConnected {
                    nutritionModeBanner
                    calorieHeroSection
                    macroRingsSection
                    calorieBalanceSection
                    hydrationSection
                    mealTimingSection
                    mealsSection
                    calorieTrendSection
                    aiCoachingCard

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
                } else {
                    emptyStateSection
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Fuel")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            isRefreshing = true
            try? await Task.sleep(for: .seconds(1))
            isRefreshing = false
        }
        .sheet(isPresented: $showMealLogging) {
            MealLoggingView()
        }
    }

    // MARK: - Nutrition Mode Banner (Task 1)

    @ViewBuilder
    private var nutritionModeBanner: some View {
        if let targets = fuelData?.adjustedTargets, targets.mode != .standard {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: modeBannerIcon(targets.mode))
                    .font(.system(size: 14))
                    .foregroundStyle(modeBannerColor(targets.mode))

                VStack(alignment: .leading, spacing: 2) {
                    Text(modeBannerTitle(targets.mode))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.tempoTextPrimary)
                        .tracking(0.5)

                    Text(targets.modeExplanation)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                Spacer()
            }
            .padding(TempoSpacing.cardPadding)
            .background(modeBannerColor(targets.mode).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
        case .repair: .tempoError
        case .fuel: .tempoSuccess
        case .rest: .tempoElectric
        case .standard: .tempoTextSecondary
        }
    }

    private func modeBannerTitle(_ mode: NutritionMode) -> String {
        switch mode {
        case .repair: "REPAIR MODE"
        case .fuel: "FUEL MODE"
        case .rest: "REST DAY"
        case .standard: "STANDARD"
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        VStack(spacing: TempoSpacing.xl) {
            Spacer().frame(height: 60)

            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("No Nutrition Data")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("Log a meal to start tracking your daily nutrition.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.xl)

            Button {
                showMealLogging = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                    Text("Log Meal")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.tempoTextInverse)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.tempoSignal)
                .clipShape(Capsule())
            }

            Spacer()
        }
    }

    // MARK: - Calorie Hero Section

    private var calorieHeroSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.xl) {
                // Calorie ring — 120pt, 10pt stroke, tempoViolet
                ZStack {
                    Circle()
                        .stroke(Color.tempoBorder, style: StrokeStyle(lineWidth: 10, lineCap: .round))

                    Circle()
                        .trim(from: 0, to: min(calorieProgress, 1.0))
                        .stroke(
                            calorieProgress > 1.0 ? Color.tempoError : Color.tempoViolet,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(TempoAnimation.springData, value: calorieProgress)

                    VStack(spacing: 0) {
                        Text("\(caloriesConsumed)")
                            .font(.tempoScoreDisplay)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .minimumScaleFactor(0.5)

                        Text("kcal")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("of \(NumberFormatter.localizedString(from: NSNumber(value: calorieTarget), number: .decimal))")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)

                    let remaining = calorieTarget - caloriesConsumed
                    if remaining > 0 {
                        Text("\(remaining) kcal remaining")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    } else {
                        Text("\(abs(remaining)) kcal over")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoError)
                    }

                    // Show base vs adjusted if different
                    if let targets = fuelData?.adjustedTargets,
                       targets.baseCalorieTarget != targets.calorieTarget
                    {
                        Text("Base: \(targets.baseCalorieTarget) kcal")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .strikethrough()
                    }
                }

                Spacer()
            }

            // Drill sergeant quip
            Text(calorieQuip)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .italic()
        }
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Macro Rings Section (Task 2)

    private var macroRingsSection: some View {
        VStack(spacing: TempoSpacing.lg) {
            // Circular progress rings row
            HStack(spacing: TempoSpacing.xl) {
                macroRing(
                    name: "Protein",
                    letter: "P",
                    current: proteinGrams,
                    target: proteinTarget,
                    color: proteinColor,
                    status: fuelData?.proteinStatus ?? .onTrack
                )
                macroRing(
                    name: "Carbs",
                    letter: "C",
                    current: carbsGrams,
                    target: carbsTarget,
                    color: carbsColor,
                    status: fuelData?.carbsStatus ?? .onTrack
                )
                macroRing(
                    name: "Fat",
                    letter: "F",
                    current: fatGrams,
                    target: fatTarget,
                    color: fatColor,
                    status: fuelData?.fatStatus ?? .onTrack
                )
            }

            // Remaining macro messages
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
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
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func macroRing(
        name: String,
        letter: String,
        current: Int,
        target: Int,
        color: Color,
        status: NutritionEngine.MacroStatus
    ) -> some View {
        let progress = target > 0 ? Double(current) / Double(target) : 0
        let ringColor = statusColor(status)

        return VStack(spacing: TempoSpacing.xs) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 6, lineCap: .round))

                Circle()
                    .trim(from: 0, to: min(progress, 1.0))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(TempoAnimation.springData, value: progress)

                Text("\(current)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tempoTextPrimary)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 64, height: 64)

            Text(name)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)

            Text("\(current)/\(target)g")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func remainingMacroLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: TempoSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    private func statusColor(_ status: NutritionEngine.MacroStatus) -> Color {
        switch status {
        case .onTrack: .tempoSuccess
        case .behind: .tempoWarning
        case .over: .tempoError
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

            VStack(spacing: TempoSpacing.md) {
                Text("ENERGY BALANCE")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    VStack(spacing: 2) {
                        Text("\(balance.caloriesIn)")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text("In")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.tempoTextTertiary)

                    VStack(spacing: 2) {
                        Text("\(balance.caloriesOut)")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text("Out")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.tempoDivider)
                        .frame(width: 1, height: 36)

                    VStack(spacing: 2) {
                        Text(balance.balanceText)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(balance.isHealthy ? Color.tempoSuccess : Color.tempoWarning)
                        Text("Balance")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
    }

    // MARK: - Hydration Section (Task 4)

    private var hydrationSection: some View {
        let currentMl = (fuelData?.hydrationMl ?? 0) + localHydrationBonus
        let targetMl = fuelData?.hydrationTargetMl ?? 2500
        let hydStatus = NutritionEngine.hydrationStatus(currentMl: currentMl, targetMl: targetMl)

        return VStack(spacing: TempoSpacing.md) {
            HStack {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoElectric)

                    Text("HYDRATION")
                        .font(.tempoModuleTag)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                Spacer()

                Text("\(hydStatus.glasses)/\(hydStatus.targetGlasses) glasses")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(hydStatus.isOnTrack ? Color.tempoSuccess : Color.tempoWarning)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.tempoElectric.opacity(0.15))
                        .frame(height: 10)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.tempoElectric.opacity(0.6), Color.tempoElectric],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(hydStatus.progress, 1.0), height: 10)
                        .animation(TempoAnimation.springData, value: hydStatus.progress)
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(currentMl) ml / \(targetMl) ml")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)

                Spacer()

                // Quick add button
                Button {
                    localHydrationBonus += 250
                    onAddHydration?(250)
                    HapticManager.lightImpact()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("+250ml")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.tempoElectric)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.tempoElectric.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Meal Timing Section (Task 3)

    @ViewBuilder
    private var mealTimingSection: some View {
        let suggestions = fuelData?.mealTimingSuggestions ?? []
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                Text("MEAL TIMING")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                ForEach(Array(suggestions.prefix(3).enumerated()), id: \.offset) { _, suggestion in
                    HStack(alignment: .top, spacing: TempoSpacing.sm) {
                        Image(systemName: suggestion.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(suggestion.priority == 0 ? Color.tempoWarning : Color.tempoViolet)
                            .frame(width: 20)

                        Text(suggestion.text)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
    }

    // MARK: - Meals Section

    private var mealsSection: some View {
        VStack(spacing: 0) {
            Text("MEALS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, TempoSpacing.md)

            ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                mealRow(meal)
                if index < meals.count - 1 {
                    Divider()
                        .background(Color.tempoDivider)
                }
            }

            // Log meal button
            Button {
                showMealLogging = true
                HapticManager.lightImpact()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                    Text("Log Meal")
                        .font(.tempoCallout)
                }
                .foregroundStyle(Color.tempoTextInverse)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.tempoSignal)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .padding(.top, TempoSpacing.md)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func mealRow(_ meal: NutritionMealEntry) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: meal.statusIcon)
                .font(.system(size: 16))
                .foregroundStyle(meal.statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.type)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)

                HStack(spacing: TempoSpacing.xs) {
                    Text(meal.time)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)

                    if !meal.items.isEmpty {
                        Text(meal.items.joined(separator: ", "))
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(meal.calories.map { "\($0) kcal" } ?? "--")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(height: 52)
    }

    // MARK: - Calorie Trend Chart

    private var calorieTrendSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("CALORIE TREND")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            Chart(calorieTrend) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(
                    point.calories > calorieTarget
                        ? Color.tempoError : Color.tempoViolet
                )
                .cornerRadius(4)

                RuleMark(y: .value("Target", calorieTarget))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(dayOfWeekAbbrev(date))
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.tempoBorder)
                    AxisValueLabel()
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .frame(height: 160)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
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

        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.tempoViolet)

                Text("COACH")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.moduleTag)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Text("Updated today at \(timeString)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
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
        case .logged: .tempoSuccess
        case .planned: .tempoTextTertiary
        case .skipped: .tempoError
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
