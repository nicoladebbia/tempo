//
// NutritionTargetSetupView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - NutritionTargetSetupView

// Onboarding/settings view for setting daily calorie and macro targets.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct NutritionTargetSetupView: View {
    @Environment(\.dismiss)
    private var dismiss

    /// Whether this is part of onboarding (shows different nav behavior)
    var isOnboarding: Bool = false
    var onSave: ((NutritionTargets) -> Void)?

    @State
    private var calorieTarget: Double = 2400
    @State
    private var selectedSplit: MacroSplit = .balanced
    @State
    private var customProteinPct: Double = 30
    @State
    private var customCarbsPct: Double = 40
    @State
    private var customFatPct: Double = 30
    @State
    private var mealsPerDay: Double = 4
    @State
    private var toast: ToastData?

    // MARK: - Macro Split Presets

    enum MacroSplit: String, CaseIterable, Identifiable {
        case balanced = "Balanced"
        case highProtein = "High Protein"
        case custom = "Custom"

        var id: String {
            rawValue
        }

        var proteinPct: Int {
            switch self {
            case .balanced: 30
            case .highProtein: 40
            case .custom: 0 // Uses custom values
            }
        }

        var carbsPct: Int {
            switch self {
            case .balanced: 40
            case .highProtein: 30
            case .custom: 0
            }
        }

        var fatPct: Int {
            switch self {
            case .balanced: 30
            case .highProtein: 30
            case .custom: 0
            }
        }
    }

    // MARK: - Computed Macros

    private var effectiveProteinPct: Int {
        selectedSplit == .custom ? Int(customProteinPct) : selectedSplit.proteinPct
    }

    private var effectiveCarbsPct: Int {
        selectedSplit == .custom ? Int(customCarbsPct) : selectedSplit.carbsPct
    }

    private var effectiveFatPct: Int {
        selectedSplit == .custom ? Int(customFatPct) : selectedSplit.fatPct
    }

    private var proteinGrams: Int {
        Int(round(calorieTarget * Double(effectiveProteinPct) / 100.0 / 4.0))
    }

    private var carbsGrams: Int {
        Int(round(calorieTarget * Double(effectiveCarbsPct) / 100.0 / 4.0))
    }

    private var fatGrams: Int {
        Int(round(calorieTarget * Double(effectiveFatPct) / 100.0 / 9.0))
    }

    private var splitSumsTo100: Bool {
        if selectedSplit != .custom {
            return true
        }
        return Int(customProteinPct) + Int(customCarbsPct) + Int(customFatPct) == 100
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.xxl) {
                    headerSection
                    calorieTargetSection
                    macroSplitSection

                    if selectedSplit == .custom {
                        customSlidersSection
                    }

                    mealsPerDaySection
                    previewCard

                    // Save button
                    Button {
                        saveTargets()
                    } label: {
                        Text("Save Targets")
                    }
                    .buttonStyle(.tempoPrimary)
                    .disabled(!splitSumsTo100)
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.top, TempoSpacing.md)
                }
                .padding(.top, TempoSpacing.lg)
                .padding(.bottom, TempoSpacing.bottomSafe)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle(isOnboarding ? "Set Targets" : "Nutrition Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
            }
            .tempoToast($toast)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: TempoSpacing.md) {
            Image(systemName: "target")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoViolet)

            Text("Set your daily fuel targets.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Calorie Target

    private var calorieTargetSection: some View {
        VStack(spacing: TempoSpacing.md) {
            Text("DAILY CALORIES")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.moduleTag)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("\(Int(calorieTarget))")
                    .font(.tempoDataLarge)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("kcal")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextTertiary)

                Spacer()
            }

            NumberStepperView(
                value: $calorieTarget,
                range: 1500 ... 5000,
                step: 50,
                format: "%.0f",
                unit: "kcal"
            )
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Macro Split Picker

    private var macroSplitSection: some View {
        VStack(spacing: TempoSpacing.md) {
            Text("MACRO SPLIT")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.moduleTag)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Macro Split", selection: $selectedSplit) {
                ForEach(MacroSplit.allCases) { split in
                    Text(split.rawValue).tag(split)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedSplit) { _, newValue in
                HapticManager.selection()
                if newValue != .custom {
                    // Reset custom values when switching away
                    customProteinPct = Double(newValue.proteinPct)
                    customCarbsPct = Double(newValue.carbsPct)
                    customFatPct = Double(newValue.fatPct)
                }
            }

            // Show preset description
            if selectedSplit != .custom {
                Text("P: \(selectedSplit.proteinPct)% / C: \(selectedSplit.carbsPct)% / F: \(selectedSplit.fatPct)%")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Custom Sliders

    private var customSlidersSection: some View {
        VStack(spacing: TempoSpacing.lg) {
            Text("CUSTOM SPLIT")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.moduleTag)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            macroSlider(
                label: "Protein",
                value: $customProteinPct,
                color: Color.tempoMacroProtein
            )

            macroSlider(
                label: "Carbs",
                value: $customCarbsPct,
                color: Color.tempoMacroCarbs
            )

            macroSlider(
                label: "Fat",
                value: $customFatPct,
                color: Color.tempoMacroFat
            )

            // Sum indicator
            let sum = Int(customProteinPct) + Int(customCarbsPct) + Int(customFatPct)
            HStack {
                Text("Total: \(sum)%")
                    .font(.tempoCaption1)
                    .foregroundStyle(sum == 100 ? Color.tempoSuccess : Color.tempoError)

                if sum != 100 {
                    Text("(must equal 100%)")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoError)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private func macroSlider(label: String, value: Binding<Double>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                Text(label)
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .font(.tempoCallout)
                    .foregroundStyle(color)
            }

            Slider(value: value, in: 10 ... 60, step: 5)
                .tint(color)
        }
    }

    // MARK: - Meals Per Day

    private var mealsPerDaySection: some View {
        VStack(spacing: TempoSpacing.md) {
            Text("MEALS PER DAY")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.moduleTag)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            NumberStepperView(
                value: $mealsPerDay,
                range: 2 ... 6,
                step: 1,
                format: "%.0f",
                unit: "meals"
            )
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(spacing: TempoSpacing.md) {
            Text("YOUR DAILY TARGETS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.moduleTag)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Main summary line
            Text(
                "\(NumberFormatter.localizedString(from: NSNumber(value: Int(calorieTarget)), number: .decimal)) kcal / P: \(proteinGrams)g / C: \(carbsGrams)g / F: \(fatGrams)g"
            )
            .font(.tempoHeadline)
            .foregroundStyle(Color.tempoTextPrimary)

            Divider().background(Color.tempoDivider)

            // Per-meal breakdown
            let mealsCount = Int(mealsPerDay)
            let calPerMeal = Int(calorieTarget) / mealsCount

            HStack {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("Per Meal (avg)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("\(calPerMeal) kcal")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: TempoSpacing.xs) {
                    Text("\(mealsCount) meals/day")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("\(effectiveProteinPct)/\(effectiveCarbsPct)/\(effectiveFatPct)")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            // Visual macro bars
            HStack(spacing: TempoSpacing.xs) {
                macroPreviewBar(
                    pct: effectiveProteinPct,
                    color: Color.tempoMacroProtein
                )
                macroPreviewBar(
                    pct: effectiveCarbsPct,
                    color: Color.tempoMacroCarbs
                )
                macroPreviewBar(
                    pct: effectiveFatPct,
                    color: Color.tempoMacroFat
                )
            }
            .frame(height: 8)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private func macroPreviewBar(pct: Int, color: Color) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(color)
                .frame(width: geo.size.width * Double(pct) / 100.0, height: 8)
        }
    }

    // MARK: - Actions

    private func saveTargets() {
        guard splitSumsTo100 else {
            toast = ToastData(message: "Macro split must equal 100%.", style: .error)
            return
        }

        let targets = NutritionTargets(
            dailyCalories: Int(calorieTarget),
            proteinPercent: effectiveProteinPct,
            carbsPercent: effectiveCarbsPct,
            fatPercent: effectiveFatPct,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            mealsPerDay: Int(mealsPerDay)
        )

        HapticManager.notification(.success)
        onSave?(targets)

        if !isOnboarding {
            toast = ToastData(message: "Targets saved.", style: .success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dismiss()
            }
        }
    }
}

// MARK: - NutritionTargets

struct NutritionTargets {
    let dailyCalories: Int
    let proteinPercent: Int
    let carbsPercent: Int
    let fatPercent: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int
    let mealsPerDay: Int
}

// MARK: - Preview

#Preview("Settings Mode") {
    NutritionTargetSetupView()
}

#Preview("Onboarding Mode") {
    NutritionTargetSetupView(isOnboarding: true)
}
