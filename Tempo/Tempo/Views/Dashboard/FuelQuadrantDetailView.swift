//
// FuelQuadrantDetailView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import SwiftUI

// MARK: - FuelQuadrantDetailView

// Per MODULE_DASHBOARD.md Section 4.3 — Fuel Expanded View.
// Calorie hero ring, macro bars, meals list, calorie trend chart, weekly averages.

struct FuelQuadrantDetailView: View {
    let data: FuelQuadrantData
    /// Annotated meal rows for today. Empty in previews unless the caller
    /// passes a `FuelDayScheduleViewModel`-populated list. Each row carries
    /// the post-shift `displayedTime`, the conflict flag, and the underlying
    /// `PlannedMeal` used for navigation.
    var mealRows: [FuelMealRow] = []
    /// Minutes by which the day's meals have been shifted forward due to a
    /// late actual wake. Zero means no shift was applied.
    var shiftMinutes: Int = 0
    var onRefreshNeeded: (() -> Void)?

    @State
    private var showNativeNutrition = false

    /// Stub 7-day calorie trend
    private let calorieTrend: [CalorieTrendPoint] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let values = [2250, 2100, 2500, 1980, 2350, 2150, 2100]
        return (-6 ... 0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            return CalorieTrendPoint(date: date, calories: values[offset + 6])
        }
    }()

    // Macro bar colors per MODULE_DASHBOARD.md Section 3.4.2
    private let proteinColor = Color.tempoMacroProtein
    private let carbsColor = Color.tempoMacroCarbs
    private let fatColor = Color.tempoMacroFat

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                if data.isConnected {
                    todayHeader
                    calorieHeroSection
                    macroSection
                    mealsSection
                    calorieTrendSection
                    weeklyAverageSection
                } else {
                    // Native nutrition empty state — log meals directly.
                    VStack(spacing: TempoSpacing.xl) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.tempoViolet)

                        Text("Track nutrition natively")
                            .font(.tempoTitle3)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Text("Log your first meal to start tracking macros, hydration, and meal timing.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)

                        VStack(spacing: TempoSpacing.buttonStackVertical) {
                            NavigationLink {
                                DailyNutritionSummaryView()
                            } label: {
                                Text("Log a Meal")
                            }
                            .buttonStyle(.tempoPrimary)
                        }
                        .padding(.horizontal, TempoSpacing.screenEdge)
                    }
                    .padding(.top, TempoSpacing.xxxxl)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Fuel")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Calorie Hero

    // Per MODULE_DASHBOARD.md Section 4.3 — Calorie Hero Section

    private var calorieHeroSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.xl) {
                // Calorie ring — 120pt
                ZStack {
                    Circle()
                        .stroke(Color.tempoBorder, style: StrokeStyle(lineWidth: 10, lineCap: .round))

                    Circle()
                        .trim(from: 0, to: min(data.calorieProgress, 1.0))
                        .stroke(
                            data.calorieProgress > 1.0 ? Color.tempoError : Color.tempoViolet,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Sized to fit comfortably inside the 120pt ring even
                    // at 4-digit kcal. tempoScoreDisplay (the previous
                    // token) was huge enough that "1,541" overflowed even
                    // with minimumScaleFactor. tempoTitle1 + tight scale
                    // floor leaves headroom for 9,999.
                    Text(data.formattedCalories)
                        .font(.tempoTitle1)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    HStack(spacing: 4) {
                        Text("of \(data.formattedCalorieTarget)")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                        Text("kcal")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
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

    // MARK: - Macro Section

    // Per MODULE_DASHBOARD.md Section 4.3 — Macro Section

    private var macroSection: some View {
        VStack(spacing: TempoSpacing.lg) {
            macroRow(
                name: "Protein",
                current: data.proteinGrams,
                target: data.proteinTarget,
                color: proteinColor,
                calPerGram: 4
            )
            macroRow(
                name: "Carbs",
                current: data.carbsGrams,
                target: data.carbsTarget,
                color: carbsColor,
                calPerGram: 4
            )
            macroRow(
                name: "Fat",
                current: data.fatGrams,
                target: data.fatTarget,
                color: fatColor,
                calPerGram: 9
            )
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func macroRow(name: String, current: Int?, target: Int?, color: Color, calPerGram: Int) -> some View {
        let progress = macroProgress(current, target)
        let currentStr = current.map { "\($0)" } ?? "--"
        let targetStr = target.map { "\($0)" } ?? "--"
        let caloriePercent = macroCaloriePercent(grams: current, calPerGram: calPerGram)

        return VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                Text(name)
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text("\(currentStr)/\(targetStr)g")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tempoBorder).frame(height: 8)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(progress, 1.0), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(caloriePercent)% of calories")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Today Header

    /// Header strip showing the calendar date and live wall-clock time.
    /// Ticks every minute via `TimelineView`. Also exposes the day's shift
    /// when meal times have been pushed forward due to a late wake.
    private var todayHeader: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.sm) {
                Text(TempoDateFormatters.dateOnly.string(from: context.date))
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("·")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextTertiary)

                Text(TempoDateFormatters.timeOnly.string(from: context.date))
                    .font(.tempoTitle3)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Spacer()

                if shiftMinutes != 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.tempoElectric)
                        Text(shiftLabel(minutes: shiftMinutes))
                            .font(.tempoCaption1)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoElectric)
                    }
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.tempoElectric.opacity(0.12))
                    .clipShape(Capsule())
                    .accessibilityLabel("Meals shifted \(abs(shiftMinutes)) minutes \(shiftMinutes > 0 ? "later" : "earlier") due to wake time")
                }
            }
            .padding(.top, TempoSpacing.md)
        }
    }

    private func shiftLabel(minutes: Int) -> String {
        let sign = minutes > 0 ? "+" : "−"
        let absMin = abs(minutes)
        if absMin < 60 {
            return "\(sign)\(absMin)m"
        }
        let h = absMin / 60
        let m = absMin % 60
        return m == 0 ? "\(sign)\(h)h" : "\(sign)\(h)h \(m)m"
    }

    // MARK: - Meals Section

    // Per MODULE_DASHBOARD.md Section 4.3 — Meals Section.
    // Renders today's `PlannedMeal`s with post-shift times and EventKit
    // "portable only" conflict badges. Tapping a row routes to
    // `MealDetailView` for the full recipe + prep flow.

    private var mealsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MEALS")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                if !mealRows.isEmpty {
                    Text("\(mealRows.count) planned")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .padding(.bottom, TempoSpacing.md)

            if mealRows.isEmpty {
                emptyMealsRow
            } else {
                ForEach(Array(mealRows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink {
                        MealDetailView(meal: row.meal)
                    } label: {
                        plannedMealRow(row)
                    }
                    .buttonStyle(.plain)

                    if index < mealRows.count - 1 {
                        Divider()
                            .background(Color.tempoDivider)
                    }
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private var emptyMealsRow: some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No meals planned for today.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
        }
        .frame(height: 48)
    }

    private func plannedMealRow(_ row: FuelMealRow) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: statusIcon(for: row.meal.status))
                .font(.system(size: 16))
                .foregroundStyle(statusColor(for: row.meal.status))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.meal.mealName)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(TempoDateFormatters.timeOnly.string(from: row.displayedTime))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .monospacedDigit()

                    if row.shiftMinutes != 0 {
                        Text("(was \(TempoDateFormatters.timeOnly.string(from: row.originalTime)))")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }

                if row.isPortableOnly {
                    portableOnlyBadge(eventTitle: row.conflictingEventTitle)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.meal.totalCalories > 0 ? "\(Int(row.meal.totalCalories)) kcal" : "—")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func portableOnlyBadge(eventTitle: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(eventTitle.map { "Portable only · \($0)" } ?? "Portable only")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .lineLimit(1)
        }
        .foregroundStyle(Color.tempoAmber)
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, 3)
        .background(Color.tempoAmber.opacity(0.15))
        .clipShape(Capsule())
    }

    private func statusIcon(for status: MealStatus) -> String {
        switch status {
        case .eaten: "checkmark.circle.fill"
        case .skipped: "xmark.circle.fill"
        default: "circle"
        }
    }

    private func statusColor(for status: MealStatus) -> Color {
        switch status {
        case .eaten: .tempoSuccess
        case .skipped: .tempoError
        default: .tempoTextTertiary
        }
    }

    // MARK: - Calorie Trend Chart

    // Per MODULE_DASHBOARD.md Section 4.3 — Calorie Trend Chart (7 Days)

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
                    point.calories > (data.calorieTarget ?? 2400)
                        ? Color.tempoError : Color.tempoViolet
                )
                .cornerRadius(4)

                if let target = data.calorieTarget {
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Color.tempoTextTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(TempoDateFormatters.shortDayOfWeek.string(from: date))
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Weekly Average

    // Per MODULE_DASHBOARD.md Section 4.3 — Weekly Average Section

    private var weeklyAverageSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("WEEKLY AVERAGE")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            Text("Calories: 2,250/day (target \(data.formattedCalorieTarget))")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("Protein: 172g/day")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)

            HStack(spacing: 4) {
                Text("Compliance:")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("82%")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoSuccess) // >= 80% = green
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Helpers

    private var calorieQuip: String {
        guard let consumed = data.caloriesConsumed,
              let target = data.calorieTarget, target > 0
        else {
            return ""
        }
        let ratio = Double(consumed) / Double(target)
        let remaining = target - consumed
        let overage = consumed - target

        switch ratio {
        case ..<0.5: return "You running on fumes?"
        case 0.5 ..< 0.8: return "Still got room for \(remaining) kcal."
        case 0.8 ... 1.0: return "On track. Don't blow it at dinner."
        case 1.0 ..< 1.2: return "Over by \(overage). Noted."
        default: return "That's a surplus, not a strategy."
        }
    }

    private func macroProgress(_ current: Int?, _ target: Int?) -> Double {
        guard let current, let target, target > 0 else {
            return 0
        }
        return Double(current) / Double(target)
    }

    private func macroCaloriePercent(grams: Int?, calPerGram: Int) -> Int {
        guard let grams, let totalCal = data.caloriesConsumed, totalCal > 0 else {
            return 0
        }
        return Int(round(Double(grams * calPerGram) / Double(totalCal) * 100))
    }
}

// MARK: - CalorieTrendPoint

struct CalorieTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Int
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FuelQuadrantDetailView(
            data: FuelQuadrantData(
                caloriesConsumed: 2100, calorieTarget: 2400,
                proteinGrams: 165, proteinTarget: 180,
                carbsGrams: 240, carbsTarget: 280,
                fatGrams: 72, fatTarget: 80,
                mealsLogged: 3, mealsPlanned: 4,
                isConnected: true, lastSync: Date()
            )
        )
    }
}
