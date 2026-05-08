//
// NutritionTodayView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
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
    @Binding
    var showMealLogging: Bool
    @Environment(\.modelContext)
    private var modelContext

    // Macro colors per MODULE_DASHBOARD.md
    private let proteinColor = Color.tempoMacroProtein
    private let carbsColor = Color.tempoMacroCarbs
    private let fatColor = Color.tempoMacroFat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.xl) {
                    macroRingsSection
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
                .padding(.bottom, 100) // Room for FAB
            }

            // Floating "Log a Meal" button
            floatingLogButton
                .padding(.trailing, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.bottomSafe)
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
                emptyMealsState
            } else {
                ForEach(viewModel.todayMeals, id: \.id) { meal in
                    PlannedMealCardView(
                        meal: meal,
                        onMarkEaten: {
                            viewModel.markMealEaten(meal, modelContext: modelContext)
                        },
                        onMarkSkipped: {
                            viewModel.markMealSkipped(meal, modelContext: modelContext)
                        }
                    )
                }
            }
        }
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

    // MARK: - Floating Log Button

    private var floatingLogButton: some View {
        Button {
            showMealLogging = true
            HapticManager.lightImpact()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text("Log a Meal")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.tempoTextInverse)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.tempoSignal)
            .clipShape(Capsule())
            .shadow(color: Color.tempoSignal.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NutritionTodayView(
            viewModel: NutritionTabViewModel(),
            showMealLogging: .constant(false)
        )
    }
    .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
