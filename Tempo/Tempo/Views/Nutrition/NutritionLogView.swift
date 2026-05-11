//
// NutritionLogView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Nutrition Log View

// Quick logging section with natural language input, photo, presets, and full search.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct NutritionLogView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Binding
    var showMealLogging: Bool
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var naturalLanguageInput: String = ""
    @State
    private var showPhotoAnalysis = false
    @State
    private var toast: ToastData?

    private let columns = [
        GridItem(.flexible(), spacing: TempoSpacing.md),
        GridItem(.flexible(), spacing: TempoSpacing.md),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                naturalLanguageSection
                quickActionsRow
                presetsSection
                fullSearchButton
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe)
        }
        .sheet(isPresented: $showPhotoAnalysis) {
            PhotoAnalysisView { _ in }
                .onDisappear {
                    viewModel.loadToday(modelContext: modelContext)
                }
        }
        .tempoToast($toast)
    }

    // MARK: - Natural Language Input

    private var naturalLanguageSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("QUICK LOG")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            HStack(spacing: TempoSpacing.sm) {
                TextField("What did you eat?", text: $naturalLanguageInput)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .padding(.horizontal, TempoSpacing.md)
                    .padding(.vertical, 12)
                    .background(Color.tempoBgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                            .stroke(Color.tempoBorder, lineWidth: 1)
                    )
                    .submitLabel(.send)
                    .onSubmit {
                        submitNaturalLanguage()
                    }

                Button {
                    submitNaturalLanguage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            naturalLanguageInput.isEmpty
                                ? Color.tempoTextDisabled
                                : Color.tempoSignal
                        )
                }
                .disabled(naturalLanguageInput.isEmpty)
            }

            Text("e.g. \"2 eggs, toast with butter, orange juice\"")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .tempoCard()
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: TempoSpacing.lg) {
            quickActionButton(icon: "camera.fill", label: "Photo") {
                showPhotoAnalysis = true
            }

            quickActionButton(icon: "magnifyingglass", label: "Full Search") {
                showMealLogging = true
            }

            quickActionButton(icon: "barcode.viewfinder", label: "Scan") {
                showMealLogging = true
            }
        }
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.lightImpact()
            action()
        }) {
            VStack(spacing: TempoSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.tempoSignal)
                    .frame(width: 52, height: 52)
                    .background(Color.tempoSignal.opacity(0.1))
                    .clipShape(Circle())

                Text(label)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack {
                Text("PRESETS")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                Spacer()

                Text("\(viewModel.sortedPresets.count) saved")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            if viewModel.sortedPresets.isEmpty {
                emptyPresetsState
            } else {
                LazyVGrid(columns: columns, spacing: TempoSpacing.md) {
                    ForEach(viewModel.sortedPresets, id: \.id) { preset in
                        presetCard(preset)
                    }
                }
            }
        }
    }

    private func presetCard(_ preset: MealPreset) -> some View {
        Button {
            viewModel.logFromPreset(preset, modelContext: modelContext)
            toast = ToastData(
                message: "\(preset.name) logged. \(Int(preset.totalCalories)) kcal.",
                style: .success
            )
        } label: {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack {
                    Image(systemName: preset.mealType.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoViolet)

                    Spacer()

                    Text("\(preset.useCount)x")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                Text(preset.name)
                    .font(.tempoCallout)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text("\(Int(preset.totalCalories))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoViolet)
                    Text("kcal")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                HStack(spacing: TempoSpacing.xs) {
                    macroLabel("P", value: Int(preset.totalProtein), color: Color.tempoMacroProtein)
                    macroLabel("C", value: Int(preset.totalCarbs), color: Color.tempoMacroCarbs)
                    macroLabel("F", value: Int(preset.totalFat), color: Color.tempoMacroFat)
                }
            }
            .tempoCard()
        }
        .buttonStyle(.plain)
    }

    private func macroLabel(_ letter: String, value: Int, color: Color) -> some View {
        Text("\(letter)\(value)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
    }

    private var emptyPresetsState: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: "bookmark")
                .font(.system(size: 24))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("No presets yet.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Text("Save your frequent meals for one-tap logging.")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xl)
        .tempoCard()
    }

    // MARK: - Full Search Button

    private var fullSearchButton: some View {
        Button {
            showMealLogging = true
            HapticManager.lightImpact()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                Text("Full Meal Search")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.tempoTextInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.tempoSignal)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
    }

    // MARK: - Actions

    private func submitNaturalLanguage() {
        guard !naturalLanguageInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        HapticManager.lightImpact()
        // Natural language parsing will be handled by Claude API
        // For now, show feedback
        toast = ToastData(
            message: "Natural language logging coming soon.",
            style: .info
        )
        naturalLanguageInput = ""
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NutritionLogView(
            viewModel: NutritionTabViewModel(),
            showMealLogging: .constant(false)
        )
    }
    .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
