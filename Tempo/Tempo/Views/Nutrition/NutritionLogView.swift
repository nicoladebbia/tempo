//
// NutritionLogView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - NutritionLogView

// Quick logging section with natural language input, photo, presets, and full search.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct NutritionLogView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Binding
    var showMealLogging: Bool
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    /// Pro / AI-off: asks for the fix instead of a "Parse failed" toast.
    @State
    private var aiBlocker: AIBlocker?
    @State
    private var naturalLanguageInput: String = ""
    /// Logged meal opened for editing (tap on a row).
    @State
    private var detailMeal: PlannedMeal?
    @State
    private var showPhotoAnalysis = false
    @State
    private var showBarcodeScanner = false
    @State
    private var showFoodCheck = false
    @State
    private var toast: ToastData?
    /// A preset the user tapped whose foods are already in today's meal —
    /// asks before logging a second portion.
    @State
    private var presetDuplicate: MealPreset?

    /// Focus on the Quick Log text field. Used so submitNaturalLanguage()
    /// can resign the keyboard the moment the user taps Go — previously the
    /// keyboard stayed up until the user tapped away.
    @FocusState
    private var quickLogFocused: Bool

    /// True while NaturalLanguageLoggingService is awaiting Haiku. Disables
    /// the Go button so the user can't double-fire.
    @State
    private var isParsing: Bool = false

    /// Foods waiting in the Confirm Meal sheet (Quick Log text). Presented on
    /// top of this screen; saved by `MealReviewHost`.
    @State
    private var reviewRequest: MealReviewRequest?

    private let columns = [
        GridItem(.flexible(), spacing: TempoSpacing.md),
        GridItem(.flexible(), spacing: TempoSpacing.md),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                naturalLanguageSection
                quickActionsRow
                loggedTodaySection
                presetsSection
                fullSearchButton
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe)
        }
        .onAppear {
            // Today's "Quick Log" button lands here with the field focused.
            if viewModel.focusQuickLogRequested {
                viewModel.focusQuickLogRequested = false
                quickLogFocused = true
            }
        }
        .navigationDestination(item: $detailMeal) { meal in
            MealDetailView(meal: meal)
        }
        .sheet(isPresented: $showPhotoAnalysis) {
            // Barcode "Add to meal" and meal photos confirm in the Confirm
            // Meal sheet right on top of the scanner.
            UniversalScanView(context: .logReview, initialMode: .mealPhoto)
                .onDisappear { viewModel.loadToday(modelContext: modelContext) }
        }
        .sheet(isPresented: $showFoodCheck) {
            FoodCheckView()
        }
        .sheet(isPresented: $showBarcodeScanner) {
            // Scan goes straight to the camera; the scanned product lands in
            // the same Confirm Meal sheet as Quick Log / Photo.
            UniversalScanView(context: .logReview, initialMode: .barcode)
        }
        .mealReview($reviewRequest) {
            naturalLanguageInput = ""
            viewModel.loadToday(modelContext: modelContext)
        }
        .tempoToast($toast)
        .aiBlockerAlert($aiBlocker) {
            submitNaturalLanguage()
        }
        .alert(
            "Already logged",
            isPresented: Binding(
                get: { presetDuplicate != nil },
                set: { if !$0 { presetDuplicate = nil } }
            ),
            presenting: presetDuplicate
        ) { preset in
            Button("Add another") {
                logPreset(preset, confirmedDuplicate: true)
                presetDuplicate = nil
            }
            Button("Cancel", role: .cancel) { presetDuplicate = nil }
        } message: { preset in
            Text("\(preset.name) is already in this meal. Log another portion?")
        }
    }

    // MARK: - Logged today (delete a wrong log)

    private var loggedToday: [PlannedMeal] {
        viewModel.todayMeals
            .filter { $0.status == .eaten }
            .sorted { ($0.actualEatenAt ?? .distantPast) > ($1.actualEatenAt ?? .distantPast) }
    }

    @ViewBuilder
    private var loggedTodaySection: some View {
        let meals = loggedToday
        if !meals.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                Text("LOGGED TODAY")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                ForEach(meals, id: \.id) { meal in
                    Button {
                        detailMeal = meal
                        HapticManager.lightImpact()
                    } label: {
                        loggedRow(meal)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the meal to edit it")
                    .swipeToDelete(label: meal.isUnplannedLog ? "Delete log" : "Undo — not eaten") {
                            undoLog(meal)
                        }
                }
            }
        }
    }

    private func loggedRow(_ meal: PlannedMeal) -> some View {
        let foods = meal.foods.map(\.name).joined(separator: ", ")
        return HStack(spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealName)
                    .font(.tempoCallout)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
                if !foods.isEmpty {
                    Text(foods)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(meal.totalCalories)) kcal")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.tempoViolet)
                if let at = meal.actualEatenAt {
                    Text(at.formatted(date: .omitted, time: .shortened))
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
        .tempoCard()
        .contextMenu {
            Button {
                detailMeal = meal
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            if !meal.foods.isEmpty {
                Button {
                    let foods = meal.foods
                    let saved = viewModel.savePreset(
                        from: meal,
                        name: foods.count == 1 ? foods[0].name : meal.mealName,
                        modelContext: modelContext
                    )
                    toast = saved
                        ? ToastData(message: "Saved as a preset.", style: .success)
                        : ToastData(message: "Couldn't save that preset. Try again.", style: .error)
                } label: {
                    Label("Save as preset", systemImage: "bookmark")
                }
            }
            Button(role: .destructive) {
                undoLog(meal)
            } label: {
                Label(meal.isUnplannedLog ? "Delete log" : "Undo — not eaten", systemImage: "trash")
            }
        }
    }

    /// Delete a wrong log (or take a plan slot back) with a 5-second Undo.
    private func undoLog(_ meal: PlannedMeal) {
        let name = meal.mealName
        guard let snapshot = viewModel.undoMealEaten(
            meal, modelContext: modelContext, notifications: services.notifications
        ) else {
            toast = ToastData(message: "Couldn't undo \(name). Try again.", style: .error)
            return
        }
        let message = snapshot.kind == .removed ? "\(name) log deleted." : "\(name) is back on the plan."
        toast = ToastData(message: message, style: .info, actionTitle: "Undo") {
            if !viewModel.restoreLog(snapshot, modelContext: modelContext, notifications: services.notifications) {
                toast = ToastData(message: "Couldn't restore \(name).", style: .error)
            }
        }
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
                    .focused($quickLogFocused)
                    .onSubmit {
                        submitNaturalLanguage()
                    }
                    .disabled(isParsing)

                Button {
                    submitNaturalLanguage()
                } label: {
                    if isParsing {
                        // Match the icon's 32pt frame so the row height
                        // doesn't shift while the request is in flight.
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                naturalLanguageInput.isEmpty
                                    ? Color.tempoTextDisabled
                                    : Color.tempoSignal
                            )
                    }
                }
                .disabled(naturalLanguageInput.isEmpty || isParsing)
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

            quickActionButton(icon: "barcode.viewfinder", label: "Scan") {
                showBarcodeScanner = true
            }

            quickActionButton(icon: "checkmark.seal", label: "Check") {
                showFoodCheck = true
            }
            .accessibilityIdentifier("nutritionCheckFood")
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
            logPreset(preset)
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
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deletePreset(preset, modelContext: modelContext)
            } label: {
                Label("Delete preset", systemImage: "trash")
            }
        }
    }

    /// Logs a preset through the shared recorder (slot match, duplicate check,
    /// legacy log, Dashboard ping). The success toast only appears when the
    /// save really happened.
    private func logPreset(_ preset: MealPreset, confirmedDuplicate: Bool = false) {
        if !confirmedDuplicate {
            let dupes = EatenMealRecorder.duplicateNames(
                of: preset.foodItems,
                type: preset.mealType,
                eatenAt: Date(),
                in: viewModel.todayMeals
            )
            if !dupes.isEmpty {
                presetDuplicate = preset
                return
            }
        }
        guard let result = viewModel.logFromPreset(
            preset,
            modelContext: modelContext,
            notifications: services.notifications
        ) else {
            toast = ToastData(message: "Couldn't log \(preset.name). Try again.", style: .error)
            return
        }
        toast = ToastData(
            message: "\(preset.name) logged. \(Int(result.logged.calories)) kcal.",
            style: .success
        )
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
        let text = naturalLanguageInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isParsing else {
            return
        }
        HapticManager.lightImpact()
        // Drop the keyboard immediately — the parse takes a moment and the
        // user shouldn't be staring at a stuck keyboard while it runs.
        quickLogFocused = false

        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                guard let request = try await MealReviewRequest.parsing(text, apiClient: services.apiClient) else {
                    toast = ToastData(
                        message: "Couldn't parse that. Try being more specific.",
                        style: .info
                    )
                    return
                }
                // Confirm Meal opens on top of this screen; nothing is saved
                // until the user taps Log there.
                reviewRequest = request
            } catch {
                if let blocker = AIBlocker(error) {
                    aiBlocker = blocker
                    return
                }
                toast = ToastData(
                    message: "Couldn't parse that: \(AIBlocker.message(for: error))",
                    style: .error
                )
            }
        }
    }

    /// Best-effort grams from a vision serving-size string. See
    /// `EatenMealRecorder.gramsFromServingSize`.
    static func gramsFromServingSize(_ serving: String) -> Double {
        EatenMealRecorder.gramsFromServingSize(serving)
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
