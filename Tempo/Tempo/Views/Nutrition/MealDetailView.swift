//
// MealDetailView.swift
// Tempo
//
// Created by Tempo on 12/05/2026.
//
//

import SwiftUI

/// Full-screen detail for a single `PlannedMeal`. Three blocks, top to bottom:
///   1. Schedule — prep-start countdown, meal time, eat-finish.
///   2. Prep checklist — auto-generated from frozen ingredients requiring defrost.
///   3. Recipe — ingredients grouped by storage location, numbered steps, macros.
///
/// Step + ingredient checkboxes are in-memory only; they reset when the view
/// disappears. Persisting them is left to a future iteration.
struct MealDetailView: View {
    let meal: PlannedMeal

    @Environment(\.dismiss)
    private var dismiss

    /// Local checklist state — keyed by ingredient / step / prep-item id.
    @State
    private var checkedIngredients: Set<UUID> = []
    @State
    private var checkedSteps: Set<UUID> = []
    @State
    private var checkedPrepItems: Set<UUID> = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                header
                scheduleSection
                if !prepChecklistItems.isEmpty {
                    prepChecklistSection
                }
                if let recipe = meal.recipe {
                    macrosSummarySection(recipe: recipe)
                    ingredientsSection(recipe: recipe)
                    stepsSection(recipe: recipe)
                } else {
                    noRecipeFallback
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle(meal.mealName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text(meal.mealName)
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)
            if let recipe = meal.recipe, let description = recipe.recipeDescription {
                Text(description)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        let prepStart = MealScheduleHelpers.prepStartDate(for: meal)
        let mealTime = MealScheduleHelpers.scheduledDate(for: meal)
        let eatFinish = MealScheduleHelpers.eatFinishDate(for: meal)

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("SCHEDULE")
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(NextMealCardView.countdownLabel(target: prepStart, now: context.date))
                    .font(.tempoBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(prepStart <= context.date ? Color.tempoSignal : Color.tempoTextPrimary)
            }
            HStack(spacing: TempoSpacing.lg) {
                scheduleChip(label: "PREP START", time: prepStart)
                scheduleChip(label: "EAT AT", time: mealTime)
                scheduleChip(label: "FINISH BY", time: eatFinish)
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func scheduleChip(label: String, time: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(Self.clockFormatter.string(from: time))
                .font(.tempoCallout)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    // MARK: - Prep Checklist

    private var prepChecklistItems: [PrepChecklistItem] {
        guard let recipe = meal.recipe else {
            return []
        }
        return recipe.orderedIngredients
            .filter(\.requiresDefrostReminder)
            .map { ingredient in
                PrepChecklistItem(
                    id: ingredient.id,
                    title: ingredient.displayName,
                    detail: "Move from freezer \(ingredient.defrostLeadTimeHours) h before mealtime"
                )
            }
    }

    private var prepChecklistSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("PREP CHECKLIST")
            ForEach(prepChecklistItems) { item in
                checklistRow(
                    id: item.id,
                    title: item.title,
                    subtitle: item.detail,
                    iconName: "snowflake",
                    isChecked: checkedPrepItems.contains(item.id),
                    toggle: { togglePrep(item.id) }
                )
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Macros

    private func macrosSummarySection(recipe: Recipe) -> some View {
        let totalMinutes = recipe.totalMinutes
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("MACROS PER SERVING")
            HStack(spacing: TempoSpacing.md) {
                macroPill(label: "CAL", value: "\(Int(recipe.totalCalories))")
                macroPill(label: "P", value: "\(Int(recipe.totalProteinGrams))g")
                macroPill(label: "C", value: "\(Int(recipe.totalCarbsGrams))g")
                macroPill(label: "F", value: "\(Int(recipe.totalFatGrams))g")
            }
            HStack(spacing: TempoSpacing.md) {
                inlineMetric(icon: "clock", text: "\(totalMinutes) min")
                inlineMetric(icon: "person.2", text: "\(recipe.servings) serving\(recipe.servings == 1 ? "" : "s")")
                inlineMetric(icon: "flame", text: recipe.difficulty.rawValue.capitalized)
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func macroPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(value)
                .font(.tempoCallout)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineMetric(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.tempoTextTertiary)
            Text(text)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Ingredients

    private func ingredientsSection(recipe: Recipe) -> some View {
        let groups = groupIngredients(recipe.orderedIngredients)
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("INGREDIENTS")
            if groups.isEmpty {
                Text("No ingredients listed.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                ForEach(groups, id: \.title) { group in
                    ingredientGroup(group)
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func ingredientGroup(_ group: IngredientGroup) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: group.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.tempoTextSecondary)
                Text(group.title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(.top, 4)

            ForEach(group.items) { ingredient in
                checklistRow(
                    id: ingredient.id,
                    title: ingredient.displayName,
                    subtitle: ingredientSubtitle(ingredient),
                    iconName: nil,
                    isChecked: checkedIngredients.contains(ingredient.id),
                    toggle: { toggleIngredient(ingredient.id) }
                )
            }
        }
    }

    private func ingredientSubtitle(_ ingredient: RecipeIngredient) -> String? {
        var parts: [String] = []
        if let qty = ingredient.displayQuantity, !qty.isEmpty {
            parts.append(qty)
        } else if ingredient.quantityGrams > 0 {
            parts.append("\(Int(ingredient.quantityGrams))g")
        }
        if let cal = ingredient.calories, cal > 0 {
            parts.append("\(Int(cal)) kcal")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Steps

    private func stepsSection(recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("STEPS")
            if recipe.orderedSteps.isEmpty {
                Text("No steps were generated for this meal.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                ForEach(recipe.orderedSteps) { step in
                    stepRow(step)
                }
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func stepRow(_ step: RecipeStep) -> some View {
        let checked = checkedSteps.contains(step.id)
        return Button {
            toggleStep(step.id)
            HapticManager.lightImpact()
        } label: {
            HStack(alignment: .top, spacing: TempoSpacing.md) {
                ZStack {
                    Circle()
                        .stroke(Color.tempoBorder, lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.tempoSuccess)
                    } else {
                        Text("\(step.orderIndex + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(step.instruction)
                        .font(.tempoBody)
                        .foregroundStyle(checked ? Color.tempoTextTertiary : Color.tempoTextPrimary)
                        .strikethrough(checked, color: Color.tempoTextTertiary)
                        .multilineTextAlignment(.leading)
                    if let duration = step.durationMinutes, duration > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.system(size: 10))
                            Text("\(duration) min")
                                .font(.tempoCaption2)
                        }
                        .foregroundStyle(Color.tempoTextTertiary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Fallback

    private var noRecipeFallback: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("RECIPE")
            Text("AI couldn't generate a recipe for this meal. Regenerate the weekly plan to retry.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Shared row + label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.tempoModuleTag)
            .tracking(TempoTracking.drillLabel)
            .foregroundStyle(Color.tempoTextSecondary)
    }

    private func checklistRow(
        id _: UUID,
        title: String,
        subtitle: String?,
        iconName: String?,
        isChecked: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: {
            toggle()
            HapticManager.lightImpact()
        }) {
            HStack(alignment: .top, spacing: TempoSpacing.md) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isChecked ? Color.tempoSuccess : Color.tempoTextTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let iconName {
                            Image(systemName: iconName)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.tempoElectric)
                        }
                        Text(title)
                            .font(.tempoBody)
                            .foregroundStyle(isChecked ? Color.tempoTextTertiary : Color.tempoTextPrimary)
                            .strikethrough(isChecked, color: Color.tempoTextTertiary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Mutation helpers

    private func toggleIngredient(_ id: UUID) {
        if checkedIngredients.contains(id) {
            checkedIngredients.remove(id)
        } else {
            checkedIngredients.insert(id)
        }
    }

    private func toggleStep(_ id: UUID) {
        if checkedSteps.contains(id) {
            checkedSteps.remove(id)
        } else {
            checkedSteps.insert(id)
        }
    }

    private func togglePrep(_ id: UUID) {
        if checkedPrepItems.contains(id) {
            checkedPrepItems.remove(id)
        } else {
            checkedPrepItems.insert(id)
        }
    }

    // MARK: - Grouping helpers

    private func groupIngredients(_ ingredients: [RecipeIngredient]) -> [IngredientGroup] {
        var bucket: [PantryStorageLocation: [RecipeIngredient]] = [:]
        var ungrouped: [RecipeIngredient] = []
        for ingredient in ingredients {
            if let loc = ingredient.storageLocation {
                bucket[loc, default: []].append(ingredient)
            } else {
                ungrouped.append(ingredient)
            }
        }
        // Display order — fridge first, then freezer, cupboard, pantry, unknown last.
        let order: [PantryStorageLocation] = [.fridge, .freezer, .cupboard, .pantry]
        var groups: [IngredientGroup] = order.compactMap { loc in
            guard let items = bucket[loc], !items.isEmpty else {
                return nil
            }
            return IngredientGroup(title: loc.displayName, icon: loc.icon, items: items)
        }
        if !ungrouped.isEmpty {
            groups.append(IngredientGroup(title: "Other", icon: "questionmark.circle", items: ungrouped))
        }
        return groups
    }

    // MARK: - Helper types

    private struct PrepChecklistItem: Identifiable {
        let id: UUID
        let title: String
        let detail: String
    }

    private struct IngredientGroup {
        let title: String
        let icon: String
        let items: [RecipeIngredient]
    }

    // MARK: - Formatters

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
