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
        // The same rounded-once totals as the Fuel hero and the product page.
        let totals = CanonicalMeals.roundedTotals(of: meals)
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(
                title: String(localized: "Logged today"),
                trailing: FuelWords.count(meals.count, "meal")
            )
            TideNumber("\(totals.calories)", unit: String(localized: "kcal"), size: Tide.numeralL)
            // How the day's calories divide, then the grams (stacked at large text sizes).
            FuelMacroSplitBar(protein: totals.protein, carbs: totals.carbs, fat: totals.fat)
            FuelMacroInline(protein: totals.protein, carbs: totals.carbs, fat: totals.fat)
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
                .init(label: meal.isUnplannedLog ? String(localized: "Delete") : String(localized: "Not eaten")) { onDelete(meal) }
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
                        Label("Save as favourite", systemImage: "star")
                    }
                }
                Button(role: .destructive) {
                    onDelete(meal)
                } label: {
                    Label(meal.isUnplannedLog ? String(localized: "Delete log") : String(localized: "Undo, not eaten"), systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - LoggedMealRow

struct LoggedMealRow: View {
    let meal: PlannedMeal

    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// Name and kcal side by side; the kcal drops under the name at accessibility sizes.
    private var titleLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s2))
    }

    private var type: MealType? {
        MealType.inferred(fromName: meal.mealName)
    }

    private var foods: String {
        meal.foods.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            TideIconTile(systemName: type?.icon ?? "fork.knife", tint: Tide.good)

            VStack(alignment: .leading, spacing: Tide.s1) {
                titleLayout {
                    Text(meal.displayMealName)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .lineLimit(3)
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s1)
                    }
                    TideNumber(
                        "\(Int(meal.totalCalories.rounded()))", unit: String(localized: "kcal"),
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
                FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s1) {
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
                FuelMacroInline(
                    protein: Int(meal.totalProtein.rounded()),
                    carbs: Int(meal.totalCarbs.rounded()),
                    fat: Int(meal.totalFat.rounded())
                )
                .padding(.top, Tide.hair)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .contentShape(.rect)
    }

    private func originBadge(_ origin: MealOrigin) -> some View {
        let isKitchen = origin == .kitchen
        return FuelPill(
            text: isKitchen ? String(localized: "Kitchen") : String(localized: "Eaten out"),
            color: isKitchen ? Tide.good : Tide.warn
        )
    }
}
