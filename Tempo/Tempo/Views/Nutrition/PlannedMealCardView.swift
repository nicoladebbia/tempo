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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tapping the header opens the full recipe page (ingredients,
            // cooking steps, schedule, macros) — the same MealDetailView the
            // Dashboard Fuel card uses. Replaces the old inline ingredient
            // expansion: the user wants the whole recipe, not a flat list.
            NavigationLink {
                MealDetailView(meal: meal)
            } label: {
                headerRow
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                HapticManager.selection()
            })

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

                timeRow
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

            // Navigation chevron — tapping the row opens the full recipe page.
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Time Row

    /// Shows planned vs actual eat-time. When the meal hasn't been
    /// eaten yet, just renders the scheduled time. When eaten, shows
    /// both with the planned time struck through and the actual time
    /// in the accent color — at a glance you can see if you stuck to
    /// the plan, ate early, or ran late.
    @ViewBuilder
    private var timeRow: some View {
        if let eaten = meal.actualEatenAt {
            HStack(spacing: 4) {
                Text(meal.scheduledTime)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
                Text(Self.clockFormatter.string(from: eaten))
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(deltaColor(eaten: eaten))
            }
        } else {
            Text(meal.scheduledTime)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    /// Green when within ±15 min of plan (on time), amber when 15–60 min
    /// off, red when >60 min off in either direction. Tracks the same
    /// ±15-min on-time window used by the smart-default in
    /// NutritionTodayView so the colors and the "skip the sheet" rule
    /// stay coherent.
    private func deltaColor(eaten: Date) -> Color {
        guard let scheduled = PlannedMealTimingMatcher.scheduledDate(for: meal, on: eaten) else {
            return Color.tempoTextSecondary
        }
        let delta = abs(eaten.timeIntervalSince(scheduled))
        if delta <= 15 * 60 { return Color.tempoSuccess }
        if delta <= 60 * 60 { return Color.tempoWarning }
        return Color.tempoError
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

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
