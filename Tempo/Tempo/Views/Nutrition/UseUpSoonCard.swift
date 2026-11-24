//
// UseUpSoonCard.swift
// Tempo
//
// Pantry FIFO surface — shows up to 3 recipes that consume soon-to-expire
// pantry items. Hidden when no items are within the 7-day urgency window
// or no candidate recipes are available. Tapping a row opens the recipe
// (RecipeDetailLoader, same as the Recipes tab).
//

import SwiftData
import SwiftUI

// MARK: - Use Up Soon Card

struct UseUpSoonCard: View {
    @Bindable var viewModel: NutritionTabViewModel

    /// Suggestions ranked by the engine that have at least one expiring ingredient.
    private var urgentSuggestions: [RecipeSuggestion] {
        viewModel.recipeState.suggestions
            .filter { $0.expiryUrgencyScore > 0 }
            .prefix(3)
            .map(\.self)
    }

    /// Compact list of expiring items keyed by canonical name → soonest days-to-expire.
    private var expiryByName: [String: Int] {
        var map: [String: Int] = [:]
        for item in viewModel.pantryState.items where item.isInStock {
            guard let days = item.daysUntilUseBy, (0 ... 7).contains(days) else {
                continue
            }
            if let existing = map[item.canonicalName], existing <= days {
                continue
            }
            map[item.canonicalName] = days
        }
        return map
    }

    var body: some View {
        if urgentSuggestions.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            // Same header as the Water and Supplements cards: icon and label
            // on the left, a live count on the right.
            let title = HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.Kitchen.warn)
                    .accessibilityHidden(true)
                Text("Use up soon").tideLabel()
            }
            let count = HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                TideNumber("\(expiryByName.count)", size: Tide.numeralS, relativeTo: .headline)
                Text(expiryByName.count == 1 ? "item expiring" : "items expiring")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    title
                    Spacer(minLength: Tide.s2)
                    if !expiryByName.isEmpty { count }
                }
                VStack(alignment: .leading, spacing: Tide.s2) {
                    title
                    if !expiryByName.isEmpty { count }
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(urgentSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 {
                        Rectangle().fill(Tide.hairline).frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    // Opens the suggested recipe, the same detail screen the
                    // Recipes tab pushes. Today is hosted in the Nutrition
                    // tab's NavigationStack, so a plain link works here.
                    NavigationLink {
                        RecipeDetailLoader(recipeID: suggestion.recipeID, viewModel: viewModel)
                    } label: {
                        row(for: suggestion)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the recipe")
                }
            }
        }
        .tideCard(padding: Tide.s4)
    }

    private func row(for suggestion: RecipeSuggestion) -> some View {
        // The expiring ingredients in this recipe: those whose canonicalName
        // appears in the expiry map. Show up to 2 in the subtitle.
        let urgentIngredients: [(name: String, days: Int)] = suggestion.presentIngredients
            .compactMap { name -> (String, Int)? in
                guard let d = expiryByName[name] else {
                    return nil
                }
                return (name, d)
            }
            .sorted { $0.1 < $1.1 }

        return HStack(alignment: .center, spacing: Tide.s3) {
            Image(systemName: "fork.knife")
                .font(Tide.bodyStrong)
                .dynamicTypeSize(.large)
                .foregroundStyle(Tide.Kitchen.warn)
                .frame(width: Tide.hit, height: Tide.hit)
                .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(suggestion.recipeName)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
                if !urgentIngredients.isEmpty {
                    Text("uses: \(urgentIngredients.prefix(2).map(\.name).joined(separator: ", "))")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
            }
            Spacer(minLength: Tide.s2)
            if let first = urgentIngredients.first {
                KitchenTag(text: urgencyLabel(days: first.days), tint: urgencyChipColor(days: first.days))
            }
            Image(systemName: "chevron.right")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Tide.s3)
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
    }

    private func urgencyLabel(days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "1 day"
        default: "\(days) days"
        }
    }

    private func urgencyChipColor(days: Int) -> Color {
        switch days {
        case 0 ... 1: Tide.danger
        case 2 ... 3: Tide.Kitchen.warn
        default: Tide.text2
        }
    }
}
