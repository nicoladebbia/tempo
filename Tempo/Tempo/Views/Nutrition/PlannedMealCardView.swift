//
// PlannedMealCardView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - Planned Meal Card View

// Individual meal card with foods, macros, status badge, and swipe actions.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct PlannedMealCardView: View {
    let meal: PlannedMeal
    var onMarkEaten: (() -> Void)?
    var onMarkSkipped: (() -> Void)?
    /// Tap handler for the "review pending" affordance shown on eaten meals
    /// that don't yet have a `MealFeedback` row. Caller decides what to
    /// present (typically `MealFeedbackSheet`).
    var onReviewTap: (() -> Void)?
    /// When true, surface the small "review" dot next to the status badge.
    /// The day list computes this from the VM's `feedbackPresence` map.
    var needsReview: Bool = false

    @State
    private var isExpanded: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            headerRow
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(TempoAnimation.springMedium) {
                        isExpanded.toggle()
                    }
                    HapticManager.selection()
                }

            // Expanded food detail
            if isExpanded {
                Divider()
                    .background(Color.tempoDivider)
                    .padding(.horizontal, TempoSpacing.sm)

                foodDetailSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Macro summary pills — always visible
            macroSummaryRow
                .padding(.top, TempoSpacing.sm)
        }
        .tempoCard()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if meal.status == .planned {
                Button {
                    onMarkSkipped?()
                } label: {
                    Label("Skip", systemImage: "xmark")
                }
                .tint(Color.tempoError)

                Button {
                    onMarkEaten?()
                } label: {
                    Label("Eaten", systemImage: "checkmark")
                }
                .tint(Color.tempoSuccess)
            }
        }
        .contextMenu {
            if meal.status == .planned {
                Button {
                    onMarkEaten?()
                } label: {
                    Label("Mark Eaten", systemImage: "checkmark.circle.fill")
                }

                Button(role: .destructive) {
                    onMarkSkipped?()
                } label: {
                    Label("Skip Meal", systemImage: "xmark.circle.fill")
                }
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: TempoSpacing.md) {
            // Meal type icon
            Image(systemName: mealIcon)
                .font(.system(size: 18))
                .foregroundStyle(mealIconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealName)
                    .font(.tempoBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text(meal.scheduledTime)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Spacer()

            // Review-pending dot — tap to leave feedback. Only visible for
            // eaten meals that don't yet have a `MealFeedback` row.
            if needsReview {
                Button {
                    HapticManager.lightImpact()
                    onReviewTap?()
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tempoAmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.tempoAmber.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leave feedback for \(meal.mealName)")
            }

            // Status badge
            statusBadge

            // Expand chevron
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.tempoTextTertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(TempoAnimation.springMedium, value: isExpanded)
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        Text(meal.status.displayName.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch meal.status {
        case .planned: .tempoTextTertiary
        case .eaten: .tempoSuccess
        case .skipped: .tempoError
        case .modified: .tempoWarning
        }
    }

    // MARK: - Food Detail

    private var foodDetailSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            let foods = meal.foods
            if foods.isEmpty {
                Text("No foods listed.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.vertical, TempoSpacing.sm)
            } else {
                ForEach(Array(foods.enumerated()), id: \.element.name) { _, food in
                    HStack(spacing: TempoSpacing.sm) {
                        Circle()
                            .fill(Color.tempoViolet.opacity(0.4))
                            .frame(width: 6, height: 6)

                        Text(food.name)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Spacer()

                        Text("\(Int(food.quantityGrams))g")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.tempoTextTertiary)

                        Text("\(Int(food.calories)) kcal")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, TempoSpacing.sm)
    }

    // MARK: - Macro Summary

    private var macroSummaryRow: some View {
        HStack(spacing: TempoSpacing.sm) {
            Text("\(Int(meal.totalCalories)) kcal")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.tempoViolet)

            Spacer()

            macroPill("P", value: Int(meal.totalProtein), color: Color.tempoMacroProtein)
            macroPill("C", value: Int(meal.totalCarbs), color: Color.tempoMacroCarbs)
            macroPill("F", value: Int(meal.totalFat), color: Color.tempoMacroFat)
        }
    }

    private func macroPill(_ label: String, value: Int, color: Color) -> some View {
        Text("\(label): \(value)g")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var mealIcon: String {
        switch meal.mealName.lowercased() {
        case "breakfast": "sunrise.fill"
        case "lunch": "sun.max.fill"
        case "dinner": "moon.stars.fill"
        case "snack": "carrot.fill"
        default: "fork.knife"
        }
    }

    private var mealIconColor: Color {
        switch meal.status {
        case .eaten: .tempoSuccess
        case .skipped: .tempoError
        case .planned: .tempoViolet
        case .modified: .tempoWarning
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: TempoSpacing.md) {
        PlannedMealCardView(
            meal: PlannedMeal(
                dayDate: Date(),
                mealNumber: 1,
                mealName: "Breakfast",
                scheduledTime: "07:30",
                foods: [
                    PlannedFood(name: "Eggs", quantityGrams: 150, calories: 220, proteinG: 18, carbsG: 1, fatG: 15),
                    PlannedFood(name: "Oatmeal", quantityGrams: 80, calories: 300, proteinG: 10, carbsG: 54, fatG: 5),
                ],
                totalCalories: 520,
                totalProtein: 28,
                totalCarbs: 55,
                totalFat: 20,
                status: .planned
            )
        )

        PlannedMealCardView(
            meal: PlannedMeal(
                dayDate: Date(),
                mealNumber: 2,
                mealName: "Lunch",
                scheduledTime: "12:30",
                totalCalories: 650,
                totalProtein: 45,
                totalCarbs: 60,
                totalFat: 22,
                status: .eaten
            )
        )
    }
    .padding()
    .background(Color.tempoBgPrimary)
}
