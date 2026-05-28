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
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var naturalLanguageInput: String = ""
    @State
    private var showPhotoAnalysis = false
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
        .sheet(item: Binding<ParsedFoodReviewPayload?>(
            get: { parsedFoodsForReview.map { ParsedFoodReviewPayload(items: $0) } },
            set: { newValue in
                if newValue == nil { parsedFoodsForReview = nil }
            }
        )) { payload in
            ParsedFoodReviewSheet(
                items: payload.items,
                defaultMealType: parsedMealTypeHint
                    ?? Self.defaultMealTypeForNow(parsedEatenAtHint ?? Date()),
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

    /// Defaults the meal-type chooser in the review sheet based on the
    /// user's local time-of-day. Breakfast, lunch, and dinner windows
    /// match the prompt anchor times used in MealPlanPrompts.
    private static func defaultMealTypeForNow(_ date: Date = Date()) -> MealType {
        // Tighter breakfast window (was < 11) — at 10:30 most people are
        // logging lunch, not breakfast. Late-evening (after 22) defaults
        // to snack because the user is more likely doing a late bite than
        // a full dinner. The user can always change it in the review
        // sheet's segmented picker.
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5 ..< 10: return .breakfast
        case 10 ..< 16: return .lunch
        case 18 ..< 22: return .dinner
        default: return .snack
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

    /// Persist the user-confirmed parsed items to MealLog. Done inline
    /// (instead of routing through MealLoggingService.logMeal) because
    /// the service's `async` signature would require sending ModelContext
    /// across actor boundaries under Swift 6 strict concurrency, and
    /// ModelContext isn't Sendable. The DB insert + save are synchronous
    /// anyway; only the HealthKit sync needs async, and that can fire
    /// from a follow-on Task with the saved MealLog (which IS Sendable).
    @MainActor
    private func persistParsedItems(
        _ items: [ParsedFoodItem],
        type: MealType,
        eatenAt: Date = Date()
    ) {
        // Map ParsedFoodItem (NL service per-item shape) onto MealFoodItem.
        let inputs = items.map { item in
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
        let foodItems = inputs.map { MealFoodItem(from: $0) }

        let totalCals = items.reduce(into: 0.0) { $0 += $1.calories }
        let totalProt = items.reduce(into: 0.0) { $0 += $1.proteinG }
        let totalCarbs = items.reduce(into: 0.0) { $0 += $1.carbsG }
        let totalFat = items.reduce(into: 0.0) { $0 += $1.fatG }

        // 1) MealLog — canonical history record. Drives Dashboard.
        // `dayDate` stays anchored to today's calendar day; `loggedAt`
        // is overridden to the user's real eat-time so the Fuel "last
        // meal X ago" and Coach context read the truth.
        let mealLog = MealLog(
            type: type,
            dayDate: Date(),
            source: .naturalLanguage,
            photo: nil,
            items: foodItems
        )
        mealLog.loggedAt = eatenAt
        modelContext.insert(mealLog)

        // 2) PlannedMeal — the row Today renders. CRITICAL: if today already
        //    has a planned meal of this MealType (e.g. plan says lunch =
        //    chicken+rice but the user ate pasta), we REPLACE the planned
        //    row in place rather than inserting a duplicate. The user's
        //    mental model is "I'm logging today's lunch", not "I'm adding
        //    a 5th meal". mealNumber = MealType.sortOrder + 1 matches the
        //    AI generator's prompt convention (1=Breakfast, 2=Lunch, …).
        let plannedFoods = items.map { item in
            PlannedFood(
                name: item.name,
                quantityGrams: item.quantityGrams,
                calories: item.calories,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG
            )
        }
        let targetMealNumber = type.sortOrder + 1

        // Phase 2: match the parsed log to a planned slot. Prefer the
        // existing same-type slot (replace-in-place), but if the user
        // typed "snack" and there are multiple snacks today, use the
        // matcher to pick the one closest to `eatenAt`.
        let candidates = viewModel.todayMeals.filter { $0.mealNumber == targetMealNumber }
        let matched = candidates.count == 1
            ? candidates.first
            : PlannedMealTimingMatcher.bestMatch(
                for: candidates,
                mealType: type.displayName,
                eatenAt: eatenAt,
                now: Date()
            )

        if let existing = matched {
            if existing.status == .eaten {
                // The meal was ALREADY logged once today — the user is
                // adding a second item (e.g. logged oat milk earlier,
                // now logging pistachios for the same breakfast). APPEND
                // foods + ADD to totals rather than overwriting, which
                // would silently delete the first item.
                let merged = existing.foods + plannedFoods
                existing.foodsJSON = try? JSONEncoder().encode(merged)
                existing.totalCalories += totalCals
                existing.totalProtein += totalProt
                existing.totalCarbs += totalCarbs
                existing.totalFat += totalFat
                // Keep the earliest eat-time; a later add shouldn't push
                // the recorded time forward.
                if let prior = existing.actualEatenAt {
                    existing.actualEatenAt = min(prior, eatenAt)
                } else {
                    existing.actualEatenAt = eatenAt
                }
                // linkedMealLogID points at the FIRST log; leave it.
            } else {
                // First log of the day for this slot — the user is telling
                // us what they actually ate instead of the AI-planned dish.
                // Replace foods + totals; keep scheduledTime/mealName so the
                // row stays in its chronological slot.
                existing.foodsJSON = try? JSONEncoder().encode(plannedFoods)
                existing.totalCalories = totalCals
                existing.totalProtein = totalProt
                existing.totalCarbs = totalCarbs
                existing.totalFat = totalFat
                existing.statusRaw = MealStatus.eaten.rawValue
                existing.linkedMealLogID = mealLog.id
                existing.actualEatenAt = eatenAt
            }
        } else {
            // No planned slot for this MealType (e.g. user is logging a
            // 4th meal on a 3-meal-plan day). Insert a new PlannedMeal
            // mirroring logFromPreset's pattern. scheduledTime mirrors
            // the user's eat-time so the row sorts into the right slot.
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let plannedMeal = PlannedMeal(
                dayDate: Date(),
                mealNumber: targetMealNumber,
                mealName: type.displayName,
                scheduledTime: timeFormatter.string(from: eatenAt),
                foods: plannedFoods,
                totalCalories: totalCals,
                totalProtein: totalProt,
                totalCarbs: totalCarbs,
                totalFat: totalFat,
                status: .eaten,
                linkedMealLogID: mealLog.id,
                actualEatenAt: eatenAt,
                mealPlan: viewModel.weeklyPlan
            )
            modelContext.insert(plannedMeal)
        }

        do {
            try modelContext.save()
        } catch {
            toast = ToastData(
                message: "Couldn't save: \(error.localizedDescription)",
                style: .error
            )
            return
        }
        toast = ToastData(
            message: "\(type.displayName) logged. \(Int(totalCals)) kcal.",
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
                        onConfirm(selectedMealType)
                        dismiss()
                    }
                    .fontWeight(.semibold)
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
