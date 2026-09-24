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

    @State
    private var naturalLanguageInput: String = ""
    @State
    private var showPhotoAnalysis = false
    @State
    private var showBarcodeScanner = false
    /// Foods confirmed in the photo-analysis or barcode sheet, stashed here so
    /// we can present the review sheet AFTER that sheet finishes dismissing
    /// (presenting synchronously inside the callback glitches sheet-over-sheet).
    @State
    private var foodsPendingReview: [ParsedFoodItem]?
    @State
    private var toast: ToastData?

    /// Focus on the Quick Log text field. Used so submitNaturalLanguage()
    /// can resign the keyboard the moment the user taps Go — previously the
    /// keyboard stayed up until the user tapped away.
    @FocusState
    private var quickLogFocused: Bool

    /// True while NaturalLanguageLoggingService is awaiting Haiku. Disables
    /// the Go button so the user can't double-fire.
    @State
    private var isParsing: Bool = false

    /// Parsed items waiting for user confirmation in the review sheet. Nil
    /// means no sheet; non-nil presents ParsedFoodReviewSheet.
    @State
    private var parsedFoodsForReview: [ParsedFoodItem]?
    /// Meal type Claude inferred from the user's text (e.g. "lunch" when
    /// they wrote "I had lunch"). Used to pre-select the review sheet's
    /// segmented picker so the user only confirms instead of choosing.
    @State
    private var parsedMealTypeHint: MealType?
    /// Eat-time Claude inferred from the user's text (e.g. "at 1pm").
    /// Falls through to `Date()` at persist time when nil — matches
    /// pre-Phase-2 behavior.
    @State
    private var parsedEatenAtHint: Date?

    /// Set when a parsed log contains a food already present in the
    /// matched meal. Presents the Add-vs-Edit alert; the buttons resume
    /// the persist with the chosen DuplicateResolution.
    @State
    private var duplicatePrompt: DuplicateFoodPrompt?

    /// Captures everything needed to finish the persist after the user
    /// picks Add or Edit. Identifiable so `.alert(item:)` can present it.
    private struct DuplicateFoodPrompt: Identifiable {
        let id = UUID()
        let items: [ParsedFoodItem]
        let type: MealType
        let eatenAt: Date
        /// Lowercased names of foods that already exist in the meal — used
        /// for the alert copy ("You already have oat milk").
        let duplicateNames: [String]
    }

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
            PhotoAnalysisView { items in
                // Stash the confirmed photo foods. quantityGrams is best-effort
                // (vision portions like "1 cup" / "diced" aren't reliably
                // grams) — it only drives the serving-size display; calories +
                // macros are the payload and carry through exactly.
                foodsPendingReview = items.map(Self.parsedFood(from:))
            }
            .onDisappear {
                presentPendingReview()
                viewModel.loadToday(modelContext: modelContext)
            }
        }
        .sheet(isPresented: $showBarcodeScanner) {
            // Scan goes straight to the camera (it used to open the full Log
            // Meal sheet first). The scanned product lands in the same review
            // sheet as Quick Log / Photo, so the user picks the meal type and
            // it's saved through the same path.
            BarcodeScannerView { item in
                foodsPendingReview = [Self.parsedFood(from: item)]
            }
            .onDisappear {
                presentPendingReview()
            }
        }
        .sheet(item: Binding<ParsedFoodReviewPayload?>(
            get: { parsedFoodsForReview.map { ParsedFoodReviewPayload(items: $0) } },
            set: { newValue in
                if newValue == nil {
                    parsedFoodsForReview = nil
                }
            }
        )) { payload in
            ParsedFoodReviewSheet(
                items: payload.items,
                defaultMealType: parsedMealTypeHint
                    ?? EatenMealRecorder.defaultMealType(for: parsedEatenAtHint ?? Date()),
                onConfirm: { mealType in
                    persistParsedItems(
                        payload.items,
                        type: mealType,
                        eatenAt: parsedEatenAtHint ?? Date()
                    )
                },
                onCancel: { parsedFoodsForReview = nil }
            )
        }
        .tempoToast($toast)
        .alert(
            "Already logged",
            isPresented: Binding(
                get: { duplicatePrompt != nil },
                set: {
                    if !$0 {
                        duplicatePrompt = nil
                    }
                }
            ),
            presenting: duplicatePrompt
        ) { prompt in
            Button("Add another") {
                commitParsed(prompt.items, type: prompt.type, eatenAt: prompt.eatenAt, resolution: .add)
                duplicatePrompt = nil
            }
            Button("Edit existing") {
                commitParsed(prompt.items, type: prompt.type, eatenAt: prompt.eatenAt, resolution: .edit)
                duplicatePrompt = nil
            }
            Button("Cancel", role: .cancel) { duplicatePrompt = nil }
        } message: { prompt in
            let names = prompt.duplicateNames.joined(separator: ", ")
            Text("You already have \(names) in this meal. Add another portion, or edit the existing one?")
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

            quickActionButton(icon: "magnifyingglass", label: "Full Search") {
                showMealLogging = true
            }

            quickActionButton(icon: "barcode.viewfinder", label: "Scan") {
                showBarcodeScanner = true
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
                let service = NaturalLanguageLoggingService(apiClient: services.apiClient)
                let parsed = try await service.parseNaturalLanguageWithTiming(text)
                guard !parsed.items.isEmpty else {
                    toast = ToastData(
                        message: "Couldn't parse that. Try being more specific.",
                        style: .info
                    )
                    return
                }
                // Stash the Claude-inferred meal-type and eat-time so the
                // review sheet defaults correctly and persist writes the
                // real eat-time into PlannedMeal.actualEatenAt.
                parsedMealTypeHint = parsed.mealType.flatMap(Self.mealType(fromHint:))
                parsedEatenAtHint = parsed.eatenAt
                // Present the parsed items for confirmation. The user picks
                // a meal type and taps Confirm — only THEN do we persist.
                parsedFoodsForReview = parsed.items
            } catch {
                toast = ToastData(
                    message: "Parse failed: \(error.localizedDescription)",
                    style: .error
                )
            }
        }
    }

    /// Maps NL parser's canonical lowercase string ("breakfast" / "lunch"
    /// / "dinner" / "snack") to a typed MealType. Returns nil for
    /// unrecognised strings so the caller falls back to time-of-day.
    private static func mealType(fromHint raw: String) -> MealType? {
        switch raw {
        case "breakfast": .breakfast
        case "lunch": .lunch
        case "dinner": .dinner
        case "snack": .snack
        default: nil
        }
    }

    /// Hands foods stashed by the photo / barcode sheet to the review sheet
    /// once that sheet has fully dismissed.
    private func presentPendingReview() {
        guard let pending = foodsPendingReview, !pending.isEmpty else {
            return
        }
        parsedFoodsForReview = pending
        parsedMealTypeHint = nil
        parsedEatenAtHint = nil
        foodsPendingReview = nil
    }

    private static func parsedFood(from food: FoodItem) -> ParsedFoodItem {
        ParsedFoodItem(
            id: food.id.uuidString,
            name: food.name,
            quantityGrams: gramsFromServingSize(food.servingSize) * food.servingQuantity,
            calories: Double(food.calories),
            proteinG: food.protein,
            carbsG: food.carbs,
            fatG: food.fat,
            isVerified: false
        )
    }

    /// Entry point after the user confirms the review sheet. If the matched
    /// meal is already eaten AND the new log repeats one of its foods, ask
    /// whether it's another portion or a fix; otherwise commit straight
    /// through (.add appends to an eaten meal; a still-planned slot is
    /// replaced inside EatenMealRecorder).
    @MainActor
    private func persistParsedItems(
        _ items: [ParsedFoodItem],
        type: MealType,
        eatenAt: Date = Date()
    ) {
        let dupes = EatenMealRecorder.duplicateNames(
            of: Self.inputs(from: items),
            type: type,
            eatenAt: eatenAt,
            in: viewModel.todayMeals
        )
        if !dupes.isEmpty {
            duplicatePrompt = DuplicateFoodPrompt(
                items: items,
                type: type,
                eatenAt: eatenAt,
                duplicateNames: dupes
            )
            return
        }
        commitParsed(items, type: type, eatenAt: eatenAt, resolution: .add)
    }

    /// Best-effort grams from a vision serving-size string. See
    /// `EatenMealRecorder.gramsFromServingSize`.
    static func gramsFromServingSize(_ serving: String) -> Double {
        EatenMealRecorder.gramsFromServingSize(serving)
    }

    private static func inputs(from items: [ParsedFoodItem]) -> [MealFoodItemInput] {
        items.map { item in
            MealFoodItemInput(
                foodId: item.id,
                name: item.name,
                brand: nil,
                servings: 1,
                servingSize: item.quantityGrams,
                servingUnit: "g",
                calories: item.calories,
                proteinGrams: item.proteinG,
                carbsGrams: item.carbsG,
                fatGrams: item.fatG,
                source: item.isVerified ? .cached : .claude
            )
        }
    }

    /// Saves the confirmed foods through EatenMealRecorder (the same path the
    /// full Log Meal sheet uses). `resolution` only matters when the matched
    /// meal is already eaten and the log repeats one of its foods:
    ///   - .add  → append (a second portion)
    ///   - .edit → replace the matching food entry, keep the others
    @MainActor
    private func commitParsed(
        _ items: [ParsedFoodItem],
        type: MealType,
        eatenAt: Date,
        resolution: EatenMealRecorder.DuplicateResolution
    ) {
        let result: EatenMealRecorder.Result
        do {
            result = try EatenMealRecorder.record(
                Self.inputs(from: items),
                type: type,
                eatenAt: eatenAt,
                source: .naturalLanguage,
                resolution: resolution,
                modelContext: modelContext,
                notifications: services.notifications
            )
        } catch {
            toast = ToastData(
                message: "Couldn't save: \(error.localizedDescription)",
                style: .error
            )
            return
        }
        toast = ToastData(
            message: "\(type.displayName) logged. \(Int(result.logged.calories)) kcal.",
            style: .success
        )
        naturalLanguageInput = ""
        parsedFoodsForReview = nil
        viewModel.loadToday(modelContext: modelContext)
    }
}

// MARK: - ParsedFoodReviewPayload

/// Identifiable wrapper so SwiftUI's `.sheet(item:)` can present the
/// review sheet from a non-Identifiable `[ParsedFoodItem]`. New UUID per
/// presentation so re-opening the sheet with the same items still fires.
private struct ParsedFoodReviewPayload: Identifiable {
    let id = UUID()
    let items: [ParsedFoodItem]
}

// MARK: - ParsedFoodReviewSheet

/// User-facing confirmation step between Haiku parsing and DB persistence.
/// Shows each parsed food row with quantity + macros, plus a meal-type
/// picker prefilled from time-of-day. Tapping Confirm fires onConfirm
/// with the user's chosen meal type; Cancel fires onCancel.
private struct ParsedFoodReviewSheet: View {
    let items: [ParsedFoodItem]
    let defaultMealType: MealType
    let onConfirm: (MealType) -> Void
    let onCancel: () -> Void

    @State
    private var selectedMealType: MealType

    /// Set on the first Log tap so a double-tap can't log the meal twice.
    @State
    private var didConfirm = false

    @Environment(\.dismiss)
    private var dismiss

    init(
        items: [ParsedFoodItem],
        defaultMealType: MealType,
        onConfirm: @escaping (MealType) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.items = items
        self.defaultMealType = defaultMealType
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedMealType = State(initialValue: defaultMealType)
    }

    private var totalCalories: Int {
        items.reduce(into: 0) { $0 += Int($1.calories) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    mealTypePicker
                    itemList
                    totalsFooter
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Confirm Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        guard !didConfirm else {
                            return
                        }
                        didConfirm = true
                        onConfirm(selectedMealType)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(didConfirm)
                }
            }
        }
    }

    private var mealTypePicker: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("MEAL TYPE")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            Picker("Meal type", selection: $selectedMealType) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("PARSED FOODS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            VStack(spacing: TempoSpacing.xs) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Text(item.formattedPortion)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                        Spacer()
                        Text("\(Int(item.calories)) kcal")
                            .font(.tempoCaption1.monospacedDigit())
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .padding(.horizontal, TempoSpacing.md)
                    .padding(.vertical, 10)
                    .background(Color.tempoBgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                }
            }
        }
    }

    private var totalsFooter: some View {
        HStack {
            Text("TOTAL")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Text("\(totalCalories) kcal")
                .font(.tempoSubheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(.top, TempoSpacing.sm)
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
