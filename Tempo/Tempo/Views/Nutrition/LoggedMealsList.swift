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

struct LoggedMealsList: View {
    let meals: [PlannedMeal]
    let onOpen: (PlannedMeal) -> Void
    let onDelete: (PlannedMeal) -> Void
    let onSavePreset: (PlannedMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
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
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("LOGGED TODAY")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                Text(meals.count == 1 ? "1 meal" : "\(meals.count) meals")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            HStack(spacing: TempoSpacing.md) {
                Text("\(Int(kcal.rounded())) kcal")
                    .font(.tempoTitle3)
                    .monospacedDigit()
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer(minLength: 0)
                MacroChip(letter: "P", grams: protein, color: .tempoMacroProtein)
                MacroChip(letter: "C", grams: carbs, color: .tempoMacroCarbs)
                MacroChip(letter: "F", grams: fat, color: .tempoMacroFat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("loggedTodayHeader")
    }

    // MARK: - Rows

    private var list: some View {
        SwipeDeleteList(
            items: meals,
            rowGap: TempoSpacing.sm,
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

// MARK: - Row

struct LoggedMealRow: View {
    let meal: PlannedMeal

    private var type: MealType? {
        MealType.inferred(fromName: meal.mealName)
    }

    private var foods: String {
        meal.foods.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            Image(systemName: type?.icon ?? "fork.knife")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.tempoViolet)
                .frame(width: 36, height: 36)
                .background(Color.tempoViolet.opacity(TempoOpacity.o15))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.sm) {
                    Text(meal.mealName)
                        .font(.tempoCallout)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: TempoSpacing.xs)
                    Text("\(Int(meal.totalCalories.rounded())) kcal")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.tempoViolet)
                        .lineLimit(1)
                        .fixedSize()
                }
                if !foods.isEmpty {
                    Text(foods)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: TempoSpacing.sm) {
                    if let at = meal.actualEatenAt {
                        Text(at.formatted(date: .omitted, time: .shortened))
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .fixedSize()
                    }
                    if let origin = meal.origin {
                        originBadge(origin)
                    }
                    Spacer(minLength: 0)
                    MacroChip(letter: "P", grams: meal.totalProtein, color: .tempoMacroProtein)
                    MacroChip(letter: "C", grams: meal.totalCarbs, color: .tempoMacroCarbs)
                    MacroChip(letter: "F", grams: meal.totalFat, color: .tempoMacroFat)
                }
                .padding(.top, 2)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        .contentShape(Rectangle())
    }

    private func originBadge(_ origin: MealOrigin) -> some View {
        let isKitchen = origin == .kitchen
        return Label(isKitchen ? "Kitchen" : "Eaten out", systemImage: isKitchen ? "refrigerator.fill" : "fork.knife")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isKitchen ? Color.tempoSuccess : Color.tempoAmber)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isKitchen ? Color.tempoSuccess : Color.tempoAmber).opacity(TempoOpacity.o15))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - MacroChip

struct MacroChip: View {
    let letter: String
    let grams: Double
    let color: Color

    var body: some View {
        Text("\(letter) \(Int(grams.rounded()))g")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}
