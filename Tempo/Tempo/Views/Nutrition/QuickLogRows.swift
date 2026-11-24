//
// QuickLogRows.swift
// Tempo
//
// The top of the capture screen: meals that log in ONE tap. Favourites (pinned
// presets) first, then "your usual" for the chosen meal type, "Same as
// yesterday", and the other saved meals. Everything comes from what the user
// really saved or logged; with no history the sections are simply absent.
// Tapping a row hands a `Choice` to the capture screen, which logs it; the
// star pins or unpins it as a favourite.
//

import SwiftData
import SwiftUI

// MARK: - QuickLogRows

struct QuickLogRows: View {
    /// One meal that can be logged in a tap.
    struct Choice: Identifiable {
        enum Kind {
            case favourite
            case usual
            case yesterday
            case saved
        }

        let id: String
        let kind: Kind
        let title: String
        let type: MealType
        let foods: [MealFoodItemInput]
        let macros: MealMacros
        let source: MealSource
        /// The saved preset behind a favourite or saved meal; nil for a derived row.
        let preset: MealPreset?
    }

    /// The meal type the rows are for.
    let type: MealType
    let onLog: (Choice) -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \MealPreset.useCount, order: .reverse)
    private var presets: [MealPreset]
    @State
    private var entries: [UsualMeals.Entry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            if !favourites.isEmpty {
                FuelRowGroup(title: "Favourites") {
                    rows(favourites)
                }
                .accessibilityIdentifier("quick.favourites")
            }
            if !usual.isEmpty {
                FuelRowGroup(title: "Your usual \(type.rawValue)") {
                    rows(usual)
                }
                .accessibilityIdentifier("quick.usual")
            }
            if let yesterday {
                FuelRowGroup(title: "Same as yesterday") {
                    rows([yesterday])
                }
                .accessibilityIdentifier("quick.yesterday")
            }
            if !saved.isEmpty {
                FuelRowGroup(title: "Saved meals") {
                    rows(saved)
                }
                .accessibilityIdentifier("quick.saved")
            }
        }
        .animation(Tide.snap, value: type)
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .tempoNutritionLogged)) { _ in
            reload()
        }
    }

    // MARK: - Data

    private func reload() {
        entries = UsualMeals.entries(in: modelContext)
    }

    private func choice(_ preset: MealPreset, kind: Choice.Kind) -> Choice {
        Choice(
            id: "preset-\(preset.id.uuidString)",
            kind: kind,
            title: preset.name,
            type: preset.mealType,
            foods: preset.foodItems,
            macros: MealMacros(
                calories: preset.totalCalories, protein: preset.totalProtein,
                carbs: preset.totalCarbs, fat: preset.totalFat
            ),
            source: .preset,
            preset: preset
        )
    }

    /// A preset is logged as the meal type chosen on screen, not the one it
    /// was saved under, so a favourite breakfast eaten at 4pm is a snack.
    private func retyped(_ choice: Choice) -> Choice {
        Choice(
            id: choice.id, kind: choice.kind, title: choice.title, type: type, foods: choice.foods,
            macros: choice.macros, source: choice.source, preset: choice.preset
        )
    }

    private var favourites: [Choice] {
        presets.filter(\.isPinned).map { retyped(choice($0, kind: .favourite)) }
    }

    private var saved: [Choice] {
        presets.filter { !$0.isPinned }.map { retyped(choice($0, kind: .saved)) }
    }

    private var usual: [Choice] {
        // A usual meal already pinned as a favourite is not shown twice.
        let pinned = Set(presets.filter(\.isPinned)
            .map { UsualMeals.signature(of: $0.foodItems.map(EatenMealRecorder.plannedFood(from:))) })
        return UsualMeals.ranked(entries, type: type)
            .filter { !pinned.contains($0.id) }
            .map(derived(_:))
    }

    private var yesterday: Choice? {
        UsualMeals.yesterday(entries, type: type).map(derived(_:))
    }

    private func derived(_ meal: UsualMeals.Usual) -> Choice {
        Choice(
            id: meal.id,
            kind: meal.id.hasPrefix("yesterday") ? .yesterday : .usual,
            title: meal.title,
            type: type,
            foods: meal.foods.map(EatenMealRecorder.input(from:)),
            macros: meal.macros,
            source: .recentMeal,
            preset: nil
        )
    }

    // MARK: - Rows

    private func rows(_ choices: [Choice]) -> some View {
        ForEach(Array(choices.enumerated()), id: \.element.id) { index, item in
            QuickLogRow(
                choice: item,
                index: index,
                onLog: { onLog(item) },
                onTogglePin: { togglePin(item) },
                onDelete: item.preset.map { preset in { delete(preset) } }
            )
        }
    }

    private func togglePin(_ choice: Choice) {
        do {
            if let preset = choice.preset {
                try MealOutcomeService.setPinned(preset, to: !preset.isPinned, modelContext: modelContext)
            } else {
                // A derived row becomes a saved meal, pinned.
                let foods = choice.foods.map(EatenMealRecorder.plannedFood(from:))
                _ = try MealOutcomeService.savePreset(
                    name: choice.title, foods: foods, mealType: choice.type, isPinned: true, modelContext: modelContext
                )
            }
            HapticManager.lightImpact()
        } catch {
            FuelLogToast.post(ToastData(message: "Couldn't save that change. Try again.", style: .error))
        }
    }

    private func delete(_ preset: MealPreset) {
        do {
            try MealOutcomeService.deletePreset(preset, modelContext: modelContext)
            HapticManager.lightImpact()
        } catch {
            FuelLogToast.post(ToastData(message: "Couldn't remove that meal. Try again.", style: .error))
        }
    }
}

// MARK: - QuickLogRow

private struct QuickLogRow: View {
    let choice: QuickLogRows.Choice
    let index: Int
    let onLog: () -> Void
    let onTogglePin: () -> Void
    let onDelete: (() -> Void)?

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var isPinned: Bool {
        choice.preset?.isPinned == true
    }

    private var identifier: String {
        switch choice.kind {
        case .favourite: "quick.favourite.\(index)"
        case .usual: "quick.usual.\(index)"
        case .yesterday: "quick.yesterday.row"
        case .saved: "quick.saved.\(index)"
        }
    }

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
    }

    var body: some View {
        HStack(spacing: Tide.s1) {
            Button {
                HapticManager.lightImpact()
                onLog()
            } label: {
                layout {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(choice.title)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        FuelMacroInline(
                            protein: Int(choice.macros.protein.rounded()),
                            carbs: Int(choice.macros.carbs.rounded()),
                            fat: Int(choice.macros.fat.rounded())
                        )
                    }
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s2)
                    }
                    TideNumber("\(Int(choice.macros.calories.rounded()))", unit: "kcal", size: Tide.numeralS, relativeTo: .headline)
                }
                .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log \(choice.title)")
            .accessibilityHint("\(Int(choice.macros.calories.rounded())) kilocalories as \(choice.type.rawValue)")
            .accessibilityIdentifier(identifier)

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(Tide.headline)
                    .foregroundStyle(isPinned ? mood.accent : Tide.text3)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "Remove \(choice.title) from favourites" : "Add \(choice.title) to favourites")
            .accessibilityIdentifier("\(identifier).pin")
        }
        .contextMenu {
            Button(action: onTogglePin) {
                Label(isPinned ? "Remove from favourites" : "Add to favourites", systemImage: isPinned ? "star.slash" : "star")
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete saved meal", systemImage: "trash")
                }
            }
        }
    }
}
