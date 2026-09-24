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
        for item in viewModel.pantryState.items where item.quantity > 0 {
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.tempoAmber)

                Text("USE UP SOON")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                Spacer()
            }

            VStack(spacing: TempoSpacing.sm) {
                ForEach(urgentSuggestions, id: \.id) { suggestion in
                    // Opens the suggested recipe — the same detail screen the
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
        .padding(TempoSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .fill(Color.tempoSurfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .strokeBorder(Color.tempoAmber.opacity(0.30), lineWidth: 1)
        )
    }

    private func row(for suggestion: RecipeSuggestion) -> some View {
        // The expiring ingredients in this recipe — those whose canonicalName
        // appears in the expiry map. Show up to 2 in the subtitle.
        let urgentIngredients: [(name: String, days: Int)] = suggestion.presentIngredients
            .compactMap { name -> (String, Int)? in
                guard let d = expiryByName[name] else {
                    return nil
                }
                return (name, d)
            }
            .sorted { $0.1 < $1.1 }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(suggestion.recipeName)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if let first = urgentIngredients.first {
                    Text(urgencyLabel(days: first.days))
                        .font(.tempoCaption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(urgencyChipColor(days: first.days).opacity(0.15))
                        )
                        .foregroundStyle(urgencyChipColor(days: first.days))
                }
            }
            HStack {
                if !urgentIngredients.isEmpty {
                    Text("uses: \(urgentIngredients.prefix(2).map(\.name).joined(separator: ", "))")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
        case 0 ... 1: Color.tempoError
        case 2 ... 3: Color.tempoAmber
        default: Color.tempoTextSecondary
        }
    }
}
