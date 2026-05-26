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
                defaultMealType: Self.defaultMealTypeForNow(),
                defaultTimestamp: Date(),
                onConfirm: { mealType, timestamp, presetName in
                    persistParsedItems(
                        payload.items,
                        type: mealType,
                        loggedAt: timestamp,
                        savePresetNamed: presetName
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
                let items = try await service.parseNaturalLanguage(text)
                guard !items.isEmpty else {
                    toast = ToastData(
                        message: "Couldn't parse that. Try being more specific.",
                        style: .info
                    )
                    return
                }
                // Present the parsed items for confirmation. The user picks
                // a meal type and taps Confirm — only THEN do we persist.
                parsedFoodsForReview = items
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
    private static func defaultMealTypeForNow(date: Date = Date()) -> MealType {
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
        loggedAt: Date,
        savePresetNamed presetName: String?
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
        //    Honor the user-picked `loggedAt`: dayDate normalizes to its
        //    calendar day, so logging "yesterday's late dinner" at 1am
        //    files under yesterday not today. Convenience init defaults
        //    `loggedAt` to now; use the long init to inject the picked one.
        let mealLog = MealLog(
            mealType: type,
            loggedAt: loggedAt,
            totalCalories: totalCals,
            totalProtein: totalProt,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            source: .naturalLanguage,
            dayDate: Calendar.current.startOfDay(for: loggedAt)
        )
        for item in foodItems {
            mealLog.items.append(item)
        }
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

        // Replace-in-place is ONLY valid when the user is logging on today's
        // calendar day — `viewModel.todayMeals` is fetched with a today-bounded
        // FetchDescriptor, so a back-dated log for yesterday must NOT
        // overwrite today's slot. If the picked timestamp falls outside
        // today, always insert a fresh PlannedMeal for the picked dayDate.
        let pickedDay = Calendar.current.startOfDay(for: loggedAt)
        let today = Calendar.current.startOfDay(for: Date())
        let isToday = pickedDay == today

        if isToday,
           let existing = viewModel.todayMeals.first(where: { $0.mealNumber == targetMealNumber }) {
            // Replace-in-place. Keep mealName from the plan so the row's
            // label stays consistent; refresh scheduledTime to the picked
            // hour so a "logged 6pm dinner at 8pm" updates the row's time,
            // not just the eaten-at provenance. Flip status to .eaten and
            // overwrite foods + totals + actualEatenAt/linkedMealLogID.
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            existing.foodsJSON = try? JSONEncoder().encode(plannedFoods)
            existing.totalCalories = totalCals
            existing.totalProtein = totalProt
            existing.totalCarbs = totalCarbs
            existing.totalFat = totalFat
            existing.statusRaw = MealStatus.eaten.rawValue
            existing.linkedMealLogID = mealLog.id
            existing.actualEatenAt = loggedAt
            existing.scheduledTime = timeFormatter.string(from: loggedAt)
        } else {
            // No planned slot for this MealType (e.g. user is logging a
            // 4th meal on a 3-meal-plan day). Insert a new PlannedMeal
            // mirroring logFromPreset's pattern. Scheduled-time and
            // dayDate derive from the picked timestamp.
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let plannedMeal = PlannedMeal(
                dayDate: Calendar.current.startOfDay(for: loggedAt),
                mealNumber: targetMealNumber,
                mealName: type.displayName,
                scheduledTime: timeFormatter.string(from: loggedAt),
                foods: plannedFoods,
                totalCalories: totalCals,
                totalProtein: totalProt,
                totalCarbs: totalCarbs,
                totalFat: totalFat,
                status: .eaten,
                linkedMealLogID: mealLog.id,
                actualEatenAt: loggedAt,
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

        // Optional preset save. The review sheet only emits a non-nil
        // name when the user ticked "Save as preset" AND typed something.
        // Re-encode using PlannedFood (same shape NutritionTabViewModel
        // expects) so the saved preset replays cleanly via logFromPreset.
        if let presetName, !presetName.trimmingCharacters(in: .whitespaces).isEmpty {
            viewModel.savePreset(
                name: presetName.trimmingCharacters(in: .whitespaces),
                items: plannedFoods,
                mealType: type,
                modelContext: modelContext
            )
        }

        let savedSuffix = (presetName?.trimmingCharacters(in: .whitespaces).isEmpty == false)
            ? " Preset saved."
            : ""
        toast = ToastData(
            message: "\(type.displayName) logged. \(Int(totalCals)) kcal.\(savedSuffix)",
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
    let defaultTimestamp: Date
    /// (mealType, loggedAt, presetName?) — `presetName` is non-nil only if
    /// the user ticked "Save as preset" AND provided a trimmed-non-empty name.
    let onConfirm: (MealType, Date, String?) -> Void
    let onCancel: () -> Void

    @State
    private var selectedMealType: MealType

    @State
    private var timestamp: Date

    @State
    private var saveAsPreset: Bool = false

    @State
    private var presetName: String = ""

    @FocusState
    private var presetFieldFocused: Bool

    @Environment(\.dismiss)
    private var dismiss

    init(
        items: [ParsedFoodItem],
        defaultMealType: MealType,
        defaultTimestamp: Date,
        onConfirm: @escaping (MealType, Date, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.items = items
        self.defaultMealType = defaultMealType
        self.defaultTimestamp = defaultTimestamp
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedMealType = State(initialValue: defaultMealType)
        _timestamp = State(initialValue: defaultTimestamp)
    }

    private var totalCalories: Int {
        items.reduce(into: 0) { $0 += Int($1.calories) }
    }

    /// Trim-and-validate the preset name. Empty/whitespace-only → nil so
    /// the parent skips the savePreset call entirely (no "" presets in DB).
    private var validatedPresetName: String? {
        guard saveAsPreset else { return nil }
        let trimmed = presetName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    mealTypePicker
                    timestampPicker
                    itemList
                    totalsFooter
                    presetSaveSection
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
                        onConfirm(selectedMealType, timestamp, validatedPresetName)
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

    /// Lets the user back-date a log ("had this at 1pm but only logging now").
    /// Range capped at +/- 7 days so an accidental tap can't write a 2024
    /// meal. `displayedComponents: [.date, .hourAndMinute]` matches the
    /// granularity MealLog/PlannedMeal actually persist.
    private var timestampPicker: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("WHEN")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            DatePicker(
                "When",
                selection: $timestamp,
                in: Self.allowedTimestampRange(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(Color.tempoSignal)
        }
    }

    private static func allowedTimestampRange(now: Date = Date()) -> ClosedRange<Date> {
        let cal = Calendar.current
        let lower = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let upper = cal.date(byAdding: .day, value: 1, to: now) ?? now
        return lower ... upper
    }

    /// "Save as preset" affordance. Hidden behind a Toggle so the default
    /// path (one-off log) doesn't surface another input. When the toggle
    /// is on, a TextField appears prefilled with a slot-derived default
    /// (e.g. "Lunch — \(first food name)") that the user can overwrite.
    private var presetSaveSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Toggle(isOn: $saveAsPreset.animation(.easeInOut(duration: 0.15))) {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.tempoViolet)
                    Text("SAVE AS PRESET")
                        .font(.tempoModuleTag)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .tint(Color.tempoSignal)
            .onChange(of: saveAsPreset) { _, newValue in
                if newValue, presetName.isEmpty {
                    presetName = defaultPresetName
                    presetFieldFocused = true
                }
            }

            if saveAsPreset {
                TextField("Preset name", text: $presetName)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .padding(.horizontal, TempoSpacing.md)
                    .padding(.vertical, 10)
                    .background(Color.tempoBgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous)
                            .stroke(Color.tempoBorder, lineWidth: 1)
                    )
                    .focused($presetFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { presetFieldFocused = false }

                Text("Tap the preset later to re-log instantly — no AI call.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private var defaultPresetName: String {
        // "Lunch — chicken & rice" style. Keeps it short; the user
        // can rewrite. First item's name is the cheapest meaningful
        // identifier without re-running the parser.
        let first = items.first?.name ?? "meal"
        return "\(selectedMealType.displayName) — \(first)"
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
