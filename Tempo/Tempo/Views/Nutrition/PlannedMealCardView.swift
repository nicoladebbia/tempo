//
// PlannedMealCardView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - Planned Meal Card View

// One meal of the day as a glass card: name and time, its status, the kcal as
// the figure, the three macros, and a long-press menu for Eaten / Skip.

struct PlannedMealCardView: View {
    let meal: PlannedMeal
    /// Opens the full meal page (the caller owns the navigation, so the card
    /// can sit inside a swipe List without a second disclosure chevron).
    var onOpen: (() -> Void)?
    var onMarkEaten: (() -> Void)?
    var onMarkSkipped: (() -> Void)?
    /// Takes an eaten/skipped meal back: a plan slot returns to planned (its
    /// original dish restored), a log added on top of the plan is deleted.
    var onUndo: (() -> Void)?
    /// Saves the logged foods as a preset for the Log tab.
    var onSavePreset: (() -> Void)?
    /// Tap handler for the "review pending" affordance shown on eaten meals
    /// that don't yet have a `MealFeedback` row. Caller decides what to
    /// present (typically `MealFeedbackSheet`).
    var onReviewTap: (() -> Void)?
    /// When true, surface the "rate this meal" prompt on the card.
    /// The day list computes this from the VM's `feedbackPresence` map.
    var needsReview: Bool = false

    @Environment(\.tideMood)
    private var mood
    @State
    private var opens = 0

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            // Tapping the header opens the full recipe page (ingredients,
            // cooking steps, schedule, macros) — the same MealDetailView the
            // Dashboard Fuel card uses.
            Button {
                opens += 1
                onOpen?()
            } label: {
                headerRow
                    .contentShape(.rect)
            }
            .buttonStyle(FuelPressStyle())

            figuresRow

            if needsReview {
                reviewPrompt
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .sensoryFeedback(.selection, trigger: opens)
        // The primary action is tap → MealDetailView, where the user marks
        // the meal eaten (with the time/feel sheet). A long-press shortcut
        // keeps Eaten/Skip one gesture away without cluttering the card or
        // competing with the tap target.
        .contextMenu {
            switch meal.status {
            case .planned,
                 .modified:
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
            case .eaten:
                if onSavePreset != nil, !meal.foods.isEmpty {
                    Button {
                        onSavePreset?()
                    } label: {
                        Label("Save as preset", systemImage: "bookmark")
                    }
                }
                if onUndo != nil {
                    Button(role: .destructive) {
                        onUndo?()
                    } label: {
                        if meal.isUnplannedLog {
                            Label("Delete log", systemImage: "trash")
                        } else {
                            Label("Undo — not eaten", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            case .skipped:
                if onUndo != nil {
                    Button {
                        onUndo?()
                    } label: {
                        Label("Undo skip", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        let icon = Image(systemName: mealIcon)
            .font(Tide.headline)
            .foregroundStyle(mealIconColor)
            .frame(width: Tide.icon, alignment: .leading)
            .accessibilityHidden(true)
        let title = VStack(alignment: .leading, spacing: Tide.hair) {
            Text(meal.mealName)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .lineLimit(2)

            timeRow
        }
        let status = FuelPill(text: meal.status.displayName, color: statusColor)
        let chevron = Image(systemName: "chevron.right")
            .font(Tide.label)
            .foregroundStyle(Tide.text3)
            .accessibilityHidden(true)

        // One row while it fits; at large text sizes the status drops under
        // the name so no word is cut or hyphenated.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                icon
                title
                Spacer(minLength: Tide.s2)
                status
                chevron
            }
            HStack(alignment: .top, spacing: Tide.s3) {
                icon
                VStack(alignment: .leading, spacing: Tide.s2) {
                    title
                    status
                }
                Spacer(minLength: Tide.s2)
                chevron
            }
        }
        .frame(minHeight: Tide.hit)
    }

    // MARK: - Time Row

    /// Shows planned vs actual eat-time. When the meal hasn't been
    /// eaten yet, just renders the scheduled time. When eaten, shows
    /// both with the planned time struck through and the actual time
    /// in the status colour — at a glance you can see if you stuck to
    /// the plan, ate early, or ran late.
    @ViewBuilder
    private var timeRow: some View {
        if let eaten = meal.actualEatenAt, Self.clockFormatter.string(from: eaten) != meal.scheduledTime {
            HStack(spacing: Tide.s1) {
                Text(meal.scheduledTime)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
                Text(Self.clockFormatter.string(from: eaten))
                    .font(Tide.caption)
                    .foregroundStyle(deltaColor(eaten: eaten))
            }
            .monospacedDigit()
        } else {
            // Either not eaten yet, or eaten exactly on the scheduled minute —
            // a "13:09 → 13:09" struck-through arrow tells you nothing
            // (picky-QA item 14), so just show the plain time.
            Text(meal.scheduledTime)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .monospacedDigit()
        }
    }

    /// Green when within ±15 min of plan (on time), amber when 15–60 min
    /// off, red when >60 min off in either direction. Tracks the same
    /// ±15-min on-time window used by the smart-default in
    /// NutritionTodayView so the colors and the "skip the sheet" rule
    /// stay coherent.
    private func deltaColor(eaten: Date) -> Color {
        guard let scheduled = PlannedMealTimingMatcher.scheduledDate(for: meal, on: eaten) else {
            return Tide.text2
        }
        let delta = abs(eaten.timeIntervalSince(scheduled))
        if delta <= 15 * 60 {
            return Tide.good
        }
        if delta <= 60 * 60 {
            return Tide.warn
        }
        return Tide.danger
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var statusColor: Color {
        switch meal.status {
        case .planned: Tide.text2
        case .eaten: Tide.good
        case .skipped: Tide.danger
        case .modified: Tide.warn
        }
    }

    // MARK: - Figures

    /// The kcal as the figure, the macros beside it.
    private var figuresRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                kcalFigure
                Spacer(minLength: Tide.s2)
                macros
            }
            VStack(alignment: .leading, spacing: Tide.s2) {
                kcalFigure
                macros
            }
        }
    }

    private var kcalFigure: some View {
        TideNumber("\(Int(meal.totalCalories))", unit: "kcal", size: Tide.numeralS, relativeTo: .headline)
    }

    private var macros: some View {
        FuelMacroInline(
            protein: Int(meal.totalProtein),
            carbs: Int(meal.totalCarbs),
            fat: Int(meal.totalFat)
        )
    }

    // MARK: - Review prompt

    /// Eaten meals without feedback ask for it: one tap opens the review sheet.
    private var reviewPrompt: some View {
        Button {
            onReviewTap?()
        } label: {
            Label("How did it sit? Rate this meal", systemImage: "text.bubble")
                .font(Tide.caption)
                .foregroundStyle(Tide.warn)
                .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(FuelPressStyle())
        .accessibilityLabel("Leave feedback for \(meal.mealName)")
    }

    // MARK: - Helpers

    private var mealIcon: String {
        FuelMealStyle.icon(forName: meal.mealName)
    }

    private var mealIconColor: Color {
        FuelMealStyle.tone(for: meal.status, accent: mood.accent)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Tide.s3) {
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
            ),
            needsReview: true
        )
    }
    .padding(Tide.edge)
    .tidePage()
}
