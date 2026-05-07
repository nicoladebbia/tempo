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
    var nutriTrackService: (any NutriTrackServiceProtocol)?
    var onRefreshNeeded: (() -> Void)?

    @State
    private var showNutriTrackConnect = false
    @State
    private var showNativeNutrition = false

    /// Stub meal data for detail view
    private let meals: [MealDisplayItem] = [
        MealDisplayItem(name: "Breakfast", time: "7:30 AM", calories: 650, status: .logged),
        MealDisplayItem(name: "Lunch", time: "12:30 PM", calories: 780, status: .logged),
        MealDisplayItem(name: "Snack", time: "4:00 PM", calories: 670, status: .logged),
        MealDisplayItem(name: "Dinner", time: "(planned)", calories: nil, status: .planned),
    ]

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
                    calorieHeroSection
                    macroSection
                    mealsSection
                    calorieTrendSection
                    weeklyAverageSection
                } else {
                    // Native nutrition mode — log meals directly without NutriTrack
                    VStack(spacing: TempoSpacing.xl) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.tempoViolet)

                        Text("Track nutrition natively")
                            .font(.tempoTitle3)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Text("Log meals manually, or connect NutriTrack for automatic tracking.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)

                        VStack(spacing: TempoSpacing.buttonStackVertical) {
                            NavigationLink {
                                DailyNutritionSummaryView()
                            } label: {
                                Text("Log Meals Manually")
                            }
                            .buttonStyle(.tempoPrimary)

                            Button("Connect NutriTrack") {
                                showNutriTrackConnect = true
                            }
                            .buttonStyle(.tempoSecondary)
                        }
                        .padding(.horizontal, TempoSpacing.screenEdge)
                    }
                    .padding(.top, TempoSpacing.xxxxl)
                    .sheet(isPresented: $showNutriTrackConnect) {
                        if let service = nutriTrackService {
                            NutriTrackConnectView(
                                nutriTrackService: service,
                                onConnected: onRefreshNeeded
                            )
                        }
                    }
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

                    Text(data.formattedCalories)
                        .font(.tempoScoreDisplay)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .minimumScaleFactor(0.6)
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

    // MARK: - Meals Section

    // Per MODULE_DASHBOARD.md Section 4.3 — Meals Section

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
            Button {} label: {
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
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func mealRow(_ meal: MealDisplayItem) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: meal.statusIcon)
                .font(.system(size: 16))
                .foregroundStyle(meal.statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(meal.time)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()

            Text(meal.calories.map { "\($0) kcal" } ?? "--")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(height: 48)
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

// MARK: - MealDisplayItem

struct MealDisplayItem: Identifiable {
    let id = UUID()
    let name: String
    let time: String
    let calories: Int?
    let status: MealDisplayStatus

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

// MARK: - MealDisplayStatus

enum MealDisplayStatus {
    case logged
    case planned
    case skipped
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
