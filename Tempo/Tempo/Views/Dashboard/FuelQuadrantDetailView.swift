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
// Calorie hero, macro bars, meals list, calorie trend chart, weekly averages.
// Every number reads the same `FuelQuadrantData` as the Fuel card on Today.

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

    /// Last 7 days of eaten-meal totals (oldest first), from
    /// `EatenNutritionHistory`. Empty in previews / before the container loads.
    var calorieTrend: [DailyEatenTotals] = []
    var onRefreshNeeded: (() -> Void)?

    @State
    private var showNativeNutrition = false

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    /// Ties a meal row to the meal page that opens from it.
    @Namespace
    private var mealZoom

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                if data.isConnected {
                    todayHeader
                    calorieHeroSection
                    mealsSection
                    calorieTrendSection
                    weeklyAverageSection
                } else {
                    // Native nutrition empty state — log meals directly.
                    // The button is the bar at the bottom of the page.
                    FuelEmptyState(
                        icon: "fork.knife.circle.fill",
                        title: String(localized: "Track nutrition natively"),
                        message: String(localized: "Log your first meal to start tracking macros, hydration, and meal timing.")
                    )
                    .padding(.top, Tide.s6)
                }
            }
            // Full width: without it the scroll view hugs narrow content.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .tidePage()
        .fuelBottomBar(isShown: !data.isConnected) {
            NavigationLink {
                DailyNutritionSummaryView()
            } label: {
                Text("Log a Meal")
            }
            .buttonStyle(.tidePrimary)
        }
        .navigationTitle("Fuel")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Calorie Hero

    // Per MODULE_DASHBOARD.md Section 4.3 — Calorie Hero + Macro Section.
    // Same structure as the Fuel card on Today: calories as the one big
    // number, then the three macros.

    private var calorieHeroSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: String(localized: "Calories"), trailing: caloriesRemaining)

            VStack(alignment: .leading, spacing: Tide.s2) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                        TideNumber(data.formattedCalories, size: Tide.numeralL)
                        Text("of \(data.formattedCalorieTarget) kcal")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    TideLevelBar(
                        progress: min(data.calorieProgress, 1),
                        color: data.calorieProgress > 1 ? Tide.danger : nil,
                        height: Tide.bar
                    )
                    .animation(Tide.settle, value: data.calorieProgress)
                }

                // Drill sergeant quip
                if !calorieQuip.isEmpty {
                    Text(calorieQuip)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(Tide.hairline)

            // The three macros as lit rings against their targets; the "% of
            // calories" reading sits in the split bar below, as one object.
            // No macro values at all (nothing connected): no rings of zeros.
            if data.proteinGrams != nil || data.carbsGrams != nil || data.fatGrams != nil {
                FuelMacroRings(
                    protein: (data.proteinGrams ?? 0, data.proteinTarget ?? 0),
                    carbs: (data.carbsGrams ?? 0, data.carbsTarget ?? 0),
                    fat: (data.fatGrams ?? 0, data.fatTarget ?? 0)
                )
            }

            if let consumed = data.caloriesConsumed, consumed > 0 {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    FuelMacroSplitBar(
                        protein: data.proteinGrams ?? 0,
                        carbs: data.carbsGrams ?? 0,
                        fat: data.fatGrams ?? 0
                    )
                    Text("How today's calories divide")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(splitSpoken)
            }
        }
        .tideCard()
    }

    /// The split bar, said out loud (it is drawn, so it needs words).
    private var splitSpoken: String {
        let protein = macroCaloriePercent(grams: data.proteinGrams, calPerGram: 4)
        let carbs = macroCaloriePercent(grams: data.carbsGrams, calPerGram: 4)
        let fat = macroCaloriePercent(grams: data.fatGrams, calPerGram: 9)
        return String(localized: "Calories divide: Protein \(protein) percent, Carbs \(carbs) percent, Fat \(fat) percent")
    }

    /// "420 left" / "80 over", like the Today card. Nil without both numbers.
    private var caloriesRemaining: String? {
        guard let consumed = data.caloriesConsumed, let target = data.calorieTarget else {
            return nil
        }
        return FuelCalorieHero.remaining(consumed: consumed, target: target)
    }

    // MARK: - Today Header

    /// Header strip showing the calendar date and live wall-clock time.
    /// Ticks every minute via `TimelineView`. Also exposes the day's shift
    /// when meal times have been pushed forward due to a late wake.
    private var todayHeader: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: Tide.s2) {
                // A quiet eyebrow: the day and the clock, small, so the calorie
                // card below is the first thing the eye lands on.
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Text(TempoDateFormatters.dateOnly.string(from: context.date))
                        .tideLabel()
                        .fixedSize(horizontal: false, vertical: true)

                    Text("·")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)

                    Text(TempoDateFormatters.timeOnly.string(from: context.date))
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, Tide.s1)

                if shiftMinutes != 0 {
                    HStack(spacing: Tide.s1) {
                        Image(systemName: "moon.zzz.fill")
                            .accessibilityHidden(true)
                        Text(shiftLabel(minutes: shiftMinutes))
                    }
                    .font(Tide.label)
                    .foregroundStyle(Tide.water)
                    .padding(.horizontal, Tide.s2)
                    .padding(.vertical, Tide.s1)
                    .background(Tide.water.opacity(0.16), in: .capsule)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        shiftMinutes > 0
                            ? String(localized: "Meals shifted \(abs(shiftMinutes)) minutes later due to wake time")
                            : String(localized: "Meals shifted \(abs(shiftMinutes)) minutes earlier due to wake time")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shiftLabel(minutes: Int) -> String {
        let sign = minutes > 0 ? "+" : "−"
        let absMin = abs(minutes)
        if absMin < 60 {
            return String(localized: "\(sign)\(absMin)m")
        }
        let h = absMin / 60
        let m = absMin % 60
        return m == 0 ? String(localized: "\(sign)\(h)h") : String(localized: "\(sign)\(h)h \(m)m")
    }

    // MARK: - Meals Section

    // Per MODULE_DASHBOARD.md Section 4.3 — Meals Section.
    // Renders today's `PlannedMeal`s with post-shift times and EventKit
    // "portable only" conflict badges. Tapping a row routes to
    // `MealDetailView` for the full recipe + prep flow.

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(
                title: String(localized: "Meals"),
                trailing: mealRows.isEmpty ? nil : String(localized: "\(mealRows.count) planned")
            )

            if mealRows.isEmpty {
                emptyMealsRow
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(mealRows.enumerated()), id: \.element.id) { index, row in
                        NavigationLink {
                            MealDetailView(meal: row.meal)
                                .navigationTransition(.zoom(sourceID: row.meal.id, in: mealZoom))
                        } label: {
                            plannedMealRow(row)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: row.meal.id, in: mealZoom)

                        if index < mealRows.count - 1 {
                            Divider()
                                .overlay(Tide.hairline)
                        }
                    }
                }
            }
        }
        .tideCard()
    }

    private var emptyMealsRow: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(Tide.headline)
                .foregroundStyle(Tide.text3)
                .frame(width: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)
            Text("No meals planned for today.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Tide.hit)
    }

    private func plannedMealRow(_ row: FuelMealRow) -> some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: Tide.s3) {
            // The meal's own symbol, tinted by how it went: green eaten,
            // red skipped, quiet grey while it is still to come.
            TideIconTile(
                systemName: FuelMealStyle.icon(forName: row.meal.mealName),
                tint: FuelMealStyle.tone(for: row.meal.status, accent: Tide.text3),
                size: Tide.hit - Tide.s2
            )

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(row.meal.displayMealName)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                FlowLayout(spacing: Tide.s2, lineSpacing: Tide.hair) {
                    // When the meal has been eaten, show the ACTUAL eat
                    // time — that's the truth the user logged, and it
                    // must match the Nutrition tab. Only fall back to the
                    // planned/shifted displayedTime for not-yet-eaten meals.
                    if let eatenAt = row.meal.actualEatenAt {
                        Text(TempoDateFormatters.timeOnly.string(from: eatenAt))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.good)
                            .monospacedDigit()
                        Text("(planned \(TempoDateFormatters.timeOnly.string(from: row.displayedTime)))")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .monospacedDigit()
                    } else {
                        Text(TempoDateFormatters.timeOnly.string(from: row.displayedTime))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .monospacedDigit()

                        if row.shiftMinutes != 0 {
                            Text("(was \(TempoDateFormatters.timeOnly.string(from: row.originalTime)))")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                                .monospacedDigit()
                        }
                    }
                }

                if row.isPortableOnly {
                    portableOnlyBadge(eventTitle: row.conflictingEventTitle)
                }
            }

            Spacer(minLength: Tide.s2)

            VStack(alignment: .trailing, spacing: Tide.s1) {
                if row.meal.totalCalories > 0 {
                    TideNumber("\(Int(row.meal.totalCalories))", unit: String(localized: "kcal"), size: Tide.numeralS, relativeTo: .headline)
                } else {
                    Text("—")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text3)
                }
                if row.meal.status == .eaten || row.meal.status == .skipped {
                    FuelPill(
                        text: row.meal.status == .eaten ? String(localized: "Eaten") : String(localized: "Skipped"),
                        color: statusColor(for: row.meal.status)
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Image(systemName: "chevron.right")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Tide.hit + Tide.s3)
        .contentShape(.rect)
    }

    private func portableOnlyBadge(eventTitle: String?) -> some View {
        HStack(spacing: Tide.s1) {
            Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                .accessibilityHidden(true)
            Text(eventTitle.map { String(localized: "Portable only · \($0)") } ?? String(localized: "Portable only"))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .font(Tide.label)
        .foregroundStyle(Tide.warn)
        .padding(.horizontal, Tide.s2)
        .padding(.vertical, Tide.s1)
        .background(Tide.warn.opacity(0.16), in: .rect(cornerRadius: Tide.s3))
    }

    private func statusColor(for status: MealStatus) -> Color {
        switch status {
        case .eaten: Tide.good
        case .skipped: Tide.danger
        default: Tide.text3
        }
    }

    // MARK: - Calorie Trend Chart

    // Per MODULE_DASHBOARD.md Section 4.3 — Calorie Trend Chart (7 Days)

    private var calorieTrendSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "Calorie trend"))

            if calorieTrend.contains(where: \.hasData) {
                trendChart
            } else {
                Text("Nothing logged this week. Log a meal and the chart starts.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .tideCard()
    }

    /// Days with no eaten meal get no bar (a gap), never a fake value.
    private var trendChart: some View {
        Chart {
            ForEach(calorieTrend.filter(\.hasData)) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Calories", point.calories)
                )
                .foregroundStyle(
                    point.calories > (data.calorieTarget ?? 2400)
                        ? Tide.danger : mood.accent
                )
                // Today is the bar to read; the days before sit back.
                .opacity(Calendar.current.isDateInToday(point.date) ? 1 : 0.55)
                .cornerRadius(Tide.s1)
            }

            if let target = data.calorieTarget {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Tide.text3)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: Tide.hair) {
                        Text("Target")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
            }
        }
        .chartXScale(domain: trendDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(TempoDateFormatters.shortDayOfWeek.string(from: date))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                    .foregroundStyle(Tide.hairline)
                AxisValueLabel()
                    .foregroundStyle(Tide.text3)
            }
        }
        .frame(height: Tide.fuelChart)
        // Axis labels stop growing at xxxLarge, or the seven day names run into
        // each other; the numbers are also read out by the label below.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("Calories eaten per day over the last 7 days")
    }

    /// Full 7-day window so empty days keep their slot on the axis.
    private var trendDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let first = calorieTrend.first?.date ?? cal.startOfDay(for: Date())
        let last = calorieTrend.last?.date ?? first
        let end = cal.date(byAdding: .day, value: 1, to: last) ?? last
        return first ... end
    }

    // MARK: - Weekly Average

    // Per MODULE_DASHBOARD.md Section 4.3 — Weekly Average Section

    private var weeklyAverageSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "Weekly average"))

            // Averaged over the days that have eaten meals — an unlogged
            // day isn't a 0 kcal day. (Replaces hardcoded 2,250 / 172g / 82%.)
            if let avg = EatenNutritionHistory.averages(of: calorieTrend) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s4))
                layout {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text("Calories").tideLabel()
                        TideNumber(avg.calories.formatted(), unit: String(localized: "kcal/day"), size: Tide.numeralS, relativeTo: .headline)
                        Text("target \(data.formattedCalorieTarget)")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text("Protein").tideLabel()
                        TideNumber("\(avg.protein)", unit: String(localized: "g/day"), size: Tide.numeralS, relativeTo: .headline)
                        if let target = data.proteinTarget {
                            Text("target \(target)")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }

                Text("Based on \(avg.daysWithData) of the last 7 days")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            } else {
                Text("No meals logged in the last 7 days.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard()
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
        case ..<0.5: return String(localized: "You running on fumes?")
        case 0.5 ..< 0.8: return String(localized: "Still got room for \(remaining) kcal.")
        case 0.8 ... 1.0: return String(localized: "On track. Don't blow it at dinner.")
        case 1.0 ..< 1.2: return String(localized: "Over by \(overage). Noted.")
        default: return String(localized: "That's a surplus, not a strategy.")
        }
    }

    private func macroCaloriePercent(grams: Int?, calPerGram: Int) -> Int {
        guard let grams, let totalCal = data.caloriesConsumed, totalCal > 0 else {
            return 0
        }
        return Int(round(Double(grams * calPerGram) / Double(totalCal) * 100))
    }
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
