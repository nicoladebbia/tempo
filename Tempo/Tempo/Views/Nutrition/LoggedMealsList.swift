//
// LoggedMealsList.swift
// Tempo
//
// "Logged today" on the Log tab: a day header with the totals, then one row
// per eaten meal. A native List row, so the swipe-to-delete button and the
// row tap never fight (the old custom swipe fired the row tap instead of
// Delete). The list never scrolls itself; it sizes to its rows and lives in
// the Log page's ScrollView.
//

import SwiftUI

// MARK: - LoggedMealsList

struct LoggedMealsList: View {
    let meals: [PlannedMeal]
    let onOpen: (PlannedMeal) -> Void
    let onDelete: (PlannedMeal) -> Void
    let onSavePreset: (PlannedMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            header
            list
        }
    }

    // MARK: - Day header

    private var header: some View {
        let kcal = meals.reduce(0) { $0 + $1.totalCalories }
        let protein = meals.reduce(0) { $0 + $1.totalProtein }
        let carbs = meals.reduce(0) { $0 + $1.totalCarbs }
        let fat = meals.reduce(0) { $0 + $1.totalFat }
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(
                title: "Logged today",
                trailing: meals.count == 1 ? "1 meal" : "\(meals.count) meals"
            )
            TideNumber("\(Int(kcal.rounded()))", unit: "kcal", size: Tide.numeralM)
            HStack(spacing: Tide.s2) {
                MacroChip(letter: "P", grams: protein, color: Tide.protein)
                MacroChip(letter: "C", grams: carbs, color: Tide.carbs)
                MacroChip(letter: "F", grams: fat, color: Tide.fat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("loggedTodayHeader")
    }

    // MARK: - Rows

    private var list: some View {
        SwipeDeleteList(
            items: meals,
            rowGap: Tide.s2,
            swipe: { meal in
                .init(label: meal.isUnplannedLog ? "Delete" : "Not eaten") { onDelete(meal) }
            }
        ) { meal in
            Button {
                HapticManager.lightImpact()
                onOpen(meal)
            } label: {
                LoggedMealRow(meal: meal)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the meal")
            .contextMenu {
                if !meal.foods.isEmpty {
                    Button {
                        onSavePreset(meal)
                    } label: {
                        Label("Save as preset", systemImage: "bookmark")
                    }
                }
                Button(role: .destructive) {
                    onDelete(meal)
                } label: {
                    Label(meal.isUnplannedLog ? "Delete log" : "Undo, not eaten", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - LoggedMealRow

struct LoggedMealRow: View {
    let meal: PlannedMeal

    @Environment(\.tideMood)
    private var mood

    private var type: MealType? {
        MealType.inferred(fromName: meal.mealName)
    }

    private var foods: String {
        meal.foods.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Image(systemName: type?.icon ?? "fork.knife")
                .font(Tide.bodyStrong)
                .foregroundStyle(mood.accent)
                .frame(width: Tide.hit - Tide.s2, height: Tide.hit - Tide.s2)
                .background(mood.accent.opacity(0.14), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Text(meal.mealName)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                    Spacer(minLength: Tide.s1)
                    TideNumber(
                        "\(Int(meal.totalCalories.rounded()))", unit: "kcal",
                        size: Tide.numeralS, relativeTo: .headline
                    )
                    .fixedSize()
                }
                if !foods.isEmpty {
                    Text(foods)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(2)
                }
                HStack(spacing: Tide.s2) {
                    if let at = meal.actualEatenAt {
                        Text(at.formatted(date: .omitted, time: .shortened))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .fixedSize()
                    }
                    if let origin = meal.origin {
                        originBadge(origin)
                    }
                }
                HStack(spacing: Tide.s1) {
                    MacroChip(letter: "P", grams: meal.totalProtein, color: Tide.protein)
                    MacroChip(letter: "C", grams: meal.totalCarbs, color: Tide.carbs)
                    MacroChip(letter: "F", grams: meal.totalFat, color: Tide.fat)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .contentShape(.rect)
    }

    private func originBadge(_ origin: MealOrigin) -> some View {
        let isKitchen = origin == .kitchen
        return FuelPill(
            text: isKitchen ? "Kitchen" : "Eaten out",
            color: isKitchen ? Tide.good : Tide.warn
        )
    }
}

// MARK: - MacroChip

struct MacroChip: View {
    let letter: String
    let grams: Double
    let color: Color

    var body: some View {
        Text("\(letter) \(Int(grams.rounded())) g")
            .font(Tide.label)
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.s1)
            .background(color.opacity(0.14), in: .capsule)
            .lineLimit(1)
            .fixedSize()
    }
}
