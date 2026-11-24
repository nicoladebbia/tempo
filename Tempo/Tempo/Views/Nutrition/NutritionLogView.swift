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

    @Environment(\.tideMood)
    private var mood

    private let columns = [
        GridItem(.flexible(), spacing: Tide.s3),
        GridItem(.flexible(), spacing: Tide.s3),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                naturalLanguageSection
                quickActionsRow
                loggedTodaySection
                presetsSection
                fullSearchButton
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s8)
            // Pin the content to the screen width so it only scrolls up and down.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
        // Logging a repeat is a question with two answers, so it gets a page of its
        // own with the answer under the thumb instead of a system alert.
        .sheet(item: $presetDuplicate) { preset in
            FuelDecisionSheet(
                icon: "square.on.square",
                title: "Already logged",
                message: "\(preset.name) is already in this meal. Log another portion?",
                primaryTitle: "Add another",
                primary: {
                    logPreset(preset, confirmedDuplicate: true)
                    presetDuplicate = nil
                },
                cancel: { presetDuplicate = nil }
            )
            .environment(\.tideInsidePage, false)
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
        if meals.isEmpty {
            loggedEmptyState
        } else {
            LoggedMealsList(
                meals: meals,
                onOpen: { detailMeal = $0 },
                onDelete: { undoLog($0) },
                onSavePreset: { savePresetFromLog($0) }
            )
        }
    }

    private var loggedEmptyState: some View {
        FuelEmptyState(
            icon: "fork.knife.circle",
            title: "Nothing logged yet today",
            message: "Type what you ate, snap a photo or scan a pack. It lands here."
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("loggedTodayEmpty")
    }

    private func savePresetFromLog(_ meal: PlannedMeal) {
        let foods = meal.foods
        let saved = viewModel.savePreset(
            from: meal,
            name: foods.count == 1 ? foods[0].name : meal.mealName,
            modelContext: modelContext
        )
        toast = saved
            ? ToastData(message: "Saved as a preset.", style: .success)
            : ToastData(message: "Couldn't save that preset. Try again.", style: .error)
    }

    /// Delete a wrong log (or take a plan slot back) with a 5-second Undo.
    private func undoLog(_ meal: PlannedMeal) {
        let name = meal.mealName
        guard let snapshot = viewModel.undoMealEaten(
            meal, modelContext: modelContext, notifications: services.notifications
        )
        else {
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
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Quick log")

            HStack(spacing: Tide.s2) {
                TextField("What did you eat?", text: $naturalLanguageInput)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fuelField()
                    .submitLabel(.send)
                    .focused($quickLogFocused)
                    .onSubmit {
                        submitNaturalLanguage()
                    }
                    .disabled(isParsing)

                Button {
                    submitNaturalLanguage()
                } label: {
                    Group {
                        if isParsing {
                            // Same footprint as the icon so the row height
                            // doesn't shift while the request is in flight.
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(Tide.title)
                                .foregroundStyle(
                                    naturalLanguageInput.isEmpty ? Tide.text3 : mood.accent
                                )
                        }
                    }
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(naturalLanguageInput.isEmpty || isParsing)
                .accessibilityLabel("Send")
            }

            Text("e.g. \"2 eggs, toast with butter, orange juice\"")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tideCard()
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        let photo = quickActionButton(icon: "camera.fill", label: "Photo", identifier: "nutritionLogPhoto") {
            showPhotoAnalysis = true
        }
        let scan = quickActionButton(icon: "barcode.viewfinder", label: "Scan", identifier: "nutritionLogScan") {
            showBarcodeScanner = true
        }
        let check = quickActionButton(icon: "checkmark.seal", label: "Check", identifier: "nutritionCheckFood") {
            showFoodCheck = true
        }
        // Three across while they fit; stacked at large text sizes.
        return GlassEffectContainer(spacing: Tide.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) {
                    photo
                    scan
                    check
                }
                VStack(spacing: Tide.s2) {
                    photo
                    scan
                    check
                }
            }
        }
    }

    private func quickActionButton(
        icon: String, label: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        FuelActionTile(icon: icon, label: label, identifier: identifier) {
            HapticManager.lightImpact()
            action()
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Presets", trailing: "\(viewModel.sortedPresets.count) saved")

            if viewModel.sortedPresets.isEmpty {
                emptyPresetsState
            } else {
                LazyVGrid(columns: columns, spacing: Tide.s3) {
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
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack {
                    Image(systemName: preset.mealType.icon)
                        .font(Tide.caption)
                        .foregroundStyle(mood.accent)
                        .accessibilityHidden(true)

                    Spacer(minLength: Tide.s2)

                    Text("\(preset.useCount)x")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .monospacedDigit()
                }

                Text(preset.name)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                TideNumber("\(Int(preset.totalCalories))", unit: "kcal", size: Tide.numeralS, relativeTo: .headline)

                HStack(spacing: Tide.s2) {
                    macroLabel("P", value: Int(preset.totalProtein), color: Tide.protein)
                    macroLabel("C", value: Int(preset.totalCarbs), color: Tide.carbs)
                    macroLabel("F", value: Int(preset.totalFat), color: Tide.fat)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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
        )
        else {
            toast = ToastData(message: "Couldn't log \(preset.name). Try again.", style: .error)
            return
        }
        toast = ToastData(
            message: "\(preset.name) logged. \(Int(result.logged.calories)) kcal.",
            style: .success
        )
    }

    private func macroLabel(_ letter: String, value: Int, color: Color) -> some View {
        Text("\(letter) \(value)")
            .font(Tide.label)
            .foregroundStyle(color)
            .monospacedDigit()
    }

    private var emptyPresetsState: some View {
        FuelEmptyState(
            icon: "bookmark",
            title: "No presets yet",
            message: "Save your frequent meals for one-tap logging."
        )
    }

    // MARK: - Full Search Button

    private var fullSearchButton: some View {
        Button {
            showMealLogging = true
            HapticManager.lightImpact()
        } label: {
            Label("Full meal search", systemImage: "magnifyingglass")
        }
        .buttonStyle(.tidePrimary)
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
