//
// MealLoggingView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - MealLoggingView

// Full-screen modal for logging a meal. Saves by itself through
// EatenMealRecorder (the same write path as Quick Log), so every presenter —
// Nutrition, Dashboard, Daily Summary, Lockdown — gets a real log without
// wiring anything.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice, haptic feedback.

struct MealLoggingView: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var selectedMealType: MealType = .init(EatenMealRecorder.defaultMealType())
    /// True between a successful save and the delayed dismiss, so a second
    /// tap can't log the same meal twice.
    @State
    private var didLog = false
    @State
    var foodItems: [FoodItem] = []
    @State
    private var showFoodSearch = false
    @State
    private var showPhotoAnalysis = false
    @State
    private var showBarcodeScanner = false
    @State
    private var showVoiceLog = false
    /// Pre-fills FoodSearchView when a low-confidence voice item taps
    /// "Search instead".
    @State
    private var searchPrefill: String?
    @State
    private var toast: ToastData?
    @State
    private var catalog: FoodCatalog?
    /// The item whose portion editor sheet is open.
    @State
    private var editingItem: FoodItem?

    var onMealLogged: (([FoodItem], MealType) -> Void)?

    /// The eat time the user SAID in a voice log ("had lunch at 1pm"). nil →
    /// now. Only used when it falls earlier today (see `resolvedEatenAt`).
    @State
    private var voiceEatTime: Date?

    /// Voice eat time when it is today and not in the future; otherwise now.
    private var resolvedEatenAt: Date {
        let now = Date()
        guard let voiceEatTime,
              Calendar.current.isDateInToday(voiceEatTime),
              voiceEatTime <= now.addingTimeInterval(60)
        else {
            return now
        }
        return min(voiceEatTime, now)
    }

    // MARK: - Meal Type

    enum MealType: String, CaseIterable, Identifiable {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
        case snack = "Snack"

        var id: String {
            rawValue
        }

        init(_ type: Tempo.MealType) {
            switch type {
            case .breakfast: self = .breakfast
            case .lunch: self = .lunch
            case .dinner: self = .dinner
            case .snack: self = .snack
            }
        }

        /// The app-wide meal type this picker value logs as.
        var appMealType: Tempo.MealType {
            switch self {
            case .breakfast: .breakfast
            case .lunch: .lunch
            case .dinner: .dinner
            case .snack: .snack
            }
        }
    }

    // MARK: - Running Totals

    private var totalCalories: Int {
        foodItems.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        foodItems.reduce(0) { $0 + $1.protein }
    }

    private var totalCarbs: Double {
        foodItems.reduce(0) { $0 + $1.carbs }
    }

    private var totalFat: Double {
        foodItems.reduce(0) { $0 + $1.fat }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.tempoBgPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Meal type picker
                    mealTypePicker

                    // Food items list or empty state
                    if foodItems.isEmpty {
                        emptyState
                    } else {
                        foodItemsList
                    }

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 140) // Room for sticky bottom bar

                // Sticky bottom bar
                stickyBottomBar
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .sheet(isPresented: $showFoodSearch) {
                FoodSearchView(
                    onFoodSelected: { item in
                        addFoodItem(item)
                    },
                    initialQuery: searchPrefill
                )
            }
            .sheet(isPresented: $showVoiceLog) {
                VoiceMealLogView(
                    onFoodSelected: { item in
                        addFoodItem(item)
                    },
                    onEatTime: { time in
                        voiceEatTime = time
                        // Pick the meal type for the time they said, like the
                        // other logging paths do.
                        selectedMealType = .init(EatenMealRecorder.defaultMealType(for: time))
                    },
                    onSearchInstead: { name in
                        searchPrefill = name
                        showFoodSearch = true
                    }
                )
            }
            .sheet(isPresented: $showPhotoAnalysis) {
                UniversalScanView(
                    context: .logMeal(
                        onFood: { item in addFoodItem(item) },
                        onMealPhoto: { items in
                            for item in items {
                                addFoodItem(item)
                            }
                        }
                    ),
                    initialMode: .mealPhoto
                )
            }
            .sheet(isPresented: $showBarcodeScanner) {
                UniversalScanView(
                    context: .logMeal(
                        onFood: { item in addFoodItem(item) },
                        onMealPhoto: { items in
                            for item in items {
                                addFoodItem(item)
                            }
                        }
                    ),
                    initialMode: .barcode
                )
            }
            .sheet(item: $editingItem) { item in
                PortionEditorView(item: item) { updated in
                    updateFoodItem(updated)
                }
                .presentationDetents([.medium])
            }
            .tempoToast($toast)
            .task {
                if catalog == nil {
                    catalog = FoodCatalog(services: services)
                }
            }
        }
    }

    // MARK: - Meal Type Picker

    private var mealTypePicker: some View {
        Picker("Meal Type", selection: $selectedMealType) {
            ForEach(MealType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .onChange(of: selectedMealType) { _, _ in
            HapticManager.selection()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "fork.knife")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)

            Text("Nothing here yet. That's on you.")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, TempoSpacing.lg)

            Text("Search, scan, or snap a photo to add food.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, TempoSpacing.sm)

            // Input method buttons
            inputMethodButtons
                .padding(.top, TempoSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Food Items List

    private var foodItemsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Input method buttons at top
                inputMethodButtons
                    .padding(.top, TempoSpacing.md)
                    .padding(.bottom, TempoSpacing.lg)

                // Items
                ForEach(foodItems) { item in
                    foodItemRow(item)

                    if item.id != foodItems.last?.id {
                        Divider()
                            .background(Color.tempoDivider)
                            .padding(.horizontal, TempoSpacing.cardPadding)
                    }
                }
            }
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.sm)
        }
    }

    // MARK: - Food Item Row

    private func foodItemRow(_ item: FoodItem) -> some View {
        HStack(spacing: TempoSpacing.md) {
            // Tapping the row opens the portion editor — logged items used
            // to be locked to whatever grams they arrived with (picky-QA
            // item 4).
            Button {
                editingItem = item
            } label: {
                HStack(spacing: TempoSpacing.md) {
                    VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                        Text(item.name)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .lineLimit(1)

                        Text(item.portionDescription)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: TempoSpacing.xxs) {
                        Text("\(item.calories) kcal")
                            .font(.tempoCallout)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Text("P: \(Int(item.protein))g")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mealItemRow")

            // Delete button
            Button {
                removeFoodItem(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.tempoTextDisabled)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TempoSpacing.cardPadding)
        .padding(.vertical, TempoSpacing.listItemVertical)
    }

    // MARK: - Input Method Buttons

    private var inputMethodButtons: some View {
        HStack(spacing: TempoSpacing.lg) {
            inputMethodButton(icon: "magnifyingglass", label: "Search") {
                showFoodSearch = true
            }

            inputMethodButton(icon: "camera.fill", label: "Photo") {
                showPhotoAnalysis = true
            }

            inputMethodButton(icon: "barcode.viewfinder", label: "Scan") {
                showBarcodeScanner = true
            }

            inputMethodButton(icon: "mic.fill", label: "Voice") {
                showVoiceLog = true
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private func inputMethodButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.lightImpact()
            action()
        }) {
            VStack(spacing: TempoSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.tempoSignal)
                    .frame(width: 56, height: 56)
                    .background(Color.tempoSignal.opacity(0.1))
                    .clipShape(Circle())

                Text(label)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sticky Bottom Bar

    private var stickyBottomBar: some View {
        VStack(spacing: TempoSpacing.md) {
            // Running totals
            if !foodItems.isEmpty {
                HStack(spacing: 0) {
                    macroChip("\(totalCalories) kcal", color: Color.tempoViolet)
                    Spacer()
                    macroChip("P: \(Int(totalProtein))g", color: Color.tempoMacroProtein)
                    Spacer()
                    macroChip("C: \(Int(totalCarbs))g", color: Color.tempoMacroCarbs)
                    Spacer()
                    macroChip("F: \(Int(totalFat))g", color: Color.tempoMacroFat)
                }
                .padding(.horizontal, TempoSpacing.xs)
            }

            // Log Meal button
            Button {
                logMeal()
            } label: {
                Text("Log Meal")
            }
            .buttonStyle(.tempoPrimary)
            .disabled(foodItems.isEmpty || didLog)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.md)
        .padding(.bottom, TempoSpacing.bottomSafe)
        .background(
            Color.tempoSurfaceCard
                .shadow(color: Color.tempoInk.opacity(0.08), radius: 8, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func macroChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.tempoCaption1)
            .fontWeight(.medium)
            .foregroundStyle(color)
    }

    // MARK: - Actions

    private func addFoodItem(_ item: FoodItem) {
        withAnimation(TempoAnimation.springMedium) {
            foodItems.append(item)
        }
        HapticManager.lightImpact()
    }

    private func removeFoodItem(_ item: FoodItem) {
        withAnimation(TempoAnimation.springMedium) {
            foodItems.removeAll { $0.id == item.id }
        }
        HapticManager.lightImpact()
    }

    /// Replaces a logged item with its re-portioned version and remembers
    /// the chosen grams for next time this product gets added.
    private func updateFoodItem(_ updated: FoodItem) {
        withAnimation(TempoAnimation.springMedium) {
            if let index = foodItems.firstIndex(where: { $0.id == updated.id }) {
                foodItems[index] = updated
            }
        }
        HapticManager.lightImpact()
        if let barcode = updated.barcode, let catalog {
            let grams = EatenMealRecorder.gramsFromServingSize(updated.servingSize) * updated.servingQuantity
            catalog.rememberPortion(grams, forBarcode: barcode, in: modelContext)
        }
    }

    private func logMeal() {
        guard !foodItems.isEmpty, !didLog else {
            return
        }
        let loggedCalories = totalCalories
        do {
            try EatenMealRecorder.record(
                foodItems.map(\.mealFoodInput),
                type: selectedMealType.appMealType,
                eatenAt: resolvedEatenAt,
                source: voiceEatTime == nil ? .manual : .voice,
                // (voice logs carry the time the user said, see resolvedEatenAt)
                modelContext: modelContext,
                notifications: services.notifications
            )
        } catch {
            HapticManager.notification(.error)
            toast = ToastData(
                message: "Couldn't save: \(error.localizedDescription)",
                style: .error
            )
            return
        }
        didLog = true
        HapticManager.notification(.success)
        onMealLogged?(foodItems, selectedMealType)
        toast = ToastData(
            message: "\(selectedMealType.rawValue) logged. \(loggedCalories) kcal.",
            style: .success
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}

// MARK: - FoodItem

struct FoodItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var brand: String?
    var servingSize: String
    var servingQuantity: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var source: FoodDataSource = .manual
    var barcode: String?

    var portionDescription: String {
        let qty = servingQuantity == 1.0
            ? servingSize
            : "\(String(format: "%.1f", servingQuantity)) x \(servingSize)"
        if let brand {
            return "\(brand) - \(qty)"
        }
        return qty
    }

    static func == (lhs: FoodItem, rhs: FoodItem) -> Bool {
        lhs.id == rhs.id
    }

    /// This item as one logged serving. `calories` and the macros already
    /// cover the whole portion (servingQuantity × servingSize), so it's a
    /// single serving of that portion; grams are best-effort for display.
    var mealFoodInput: MealFoodItemInput {
        MealFoodItemInput(
            foodId: id.uuidString,
            name: name,
            brand: brand,
            servings: 1,
            servingSize: EatenMealRecorder.gramsFromServingSize(servingSize) * servingQuantity,
            servingUnit: "g",
            calories: Double(calories),
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            source: source,
            barcode: barcode
        )
    }
}

// MARK: - PortionEditorView

/// Lets you resize a logged item's portion before saving — a grams field
/// plus quick chips for ½ / 1 / 2× the original serving and a flat 100 g/ml,
/// with calories and macros recalculated live from the item's own density
/// (its label kcal per gram), never reset to a generic default. Falls back
/// to a plain servings stepper when the serving size has no parseable
/// gram/ml amount (e.g. "1 slice") — picky-QA item 4.
struct PortionEditorView: View {
    let item: FoodItem
    let onSave: (FoodItem) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var grams: Double
    @State
    private var gramsText: String

    /// Grams (or ml) for one serving as originally logged — the basis for
    /// the quick chips and the density used to rescale macros. `0` when the
    /// serving size has no parseable amount, in which case `grams` instead
    /// tracks a plain serving COUNT (e.g. "2.0" for "2 slices") and the
    /// densities below are per one serving, not per gram.
    private let unitGrams: Double
    private let densityKcal: Double
    private let densityProtein: Double
    private let densityCarbs: Double
    private let densityFat: Double

    init(item: FoodItem, onSave: @escaping (FoodItem) -> Void) {
        self.item = item
        self.onSave = onSave
        let parsedUnit = EatenMealRecorder.gramsFromServingSize(item.servingSize)
        unitGrams = parsedUnit
        if parsedUnit > 0 {
            let currentGrams = parsedUnit * item.servingQuantity
            let baseline = currentGrams > 0 ? currentGrams : parsedUnit
            densityKcal = baseline > 0 ? Double(item.calories) / baseline : 0
            densityProtein = baseline > 0 ? item.protein / baseline : 0
            densityCarbs = baseline > 0 ? item.carbs / baseline : 0
            densityFat = baseline > 0 ? item.fat / baseline : 0
            _grams = State(initialValue: baseline)
            _gramsText = State(initialValue: Self.format(baseline))
        } else {
            // No parseable gram amount (e.g. "1 slice") — seed with the
            // item's own serving count so opening the sheet with no changes
            // doesn't silently reset it to 1 (it used to, via a hard-coded
            // 100 g/ml stand-in baseline unrelated to the real quantity).
            let servings = item.servingQuantity > 0 ? item.servingQuantity : 1
            densityKcal = servings > 0 ? Double(item.calories) / servings : 0
            densityProtein = servings > 0 ? item.protein / servings : 0
            densityCarbs = servings > 0 ? item.carbs / servings : 0
            densityFat = servings > 0 ? item.fat / servings : 0
            _grams = State(initialValue: servings)
            _gramsText = State(initialValue: Self.format(servings))
        }
    }

    private var unitLabel: String {
        item.servingSize.lowercased().contains("ml") ? "ml" : "g"
    }

    private var previewCalories: Int {
        Int((densityKcal * grams).rounded())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.xl) {
                VStack(spacing: TempoSpacing.xxs) {
                    Text(item.name)
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .multilineTextAlignment(.center)
                    if let brand = item.brand {
                        Text(brand)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .padding(.top, TempoSpacing.lg)

                if unitGrams > 0 {
                    gramsField
                    quickChips
                } else {
                    servingsStepper
                }

                VStack(spacing: TempoSpacing.xxs) {
                    Text("\(previewCalories) kcal")
                        .font(.tempoTitle2)
                        .monospacedDigit()
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(
                        "P \(Int((densityProtein * grams).rounded()))g · " +
                            "C \(Int((densityCarbs * grams).rounded()))g · " +
                            "F \(Int((densityFat * grams).rounded()))g"
                    )
                    .font(.tempoCaption1)
                    .monospacedDigit()
                    .foregroundStyle(Color.tempoTextSecondary)
                }

                Spacer(minLength: 0)

                Button {
                    save()
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                .disabled(grams <= 0)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.lg)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Edit portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
    }

    private var gramsField: some View {
        HStack(spacing: TempoSpacing.xxs) {
            TextField(unitLabel, text: $gramsText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.tempoTitle2)
                .monospacedDigit()
                .frame(width: 90)
                .accessibilityIdentifier("portionEditorGrams")
                .onChange(of: gramsText) { _, text in
                    if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0, value <= 5000 {
                        grams = value
                    }
                }
            Text(unitLabel)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoBgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
    }

    private var quickChips: some View {
        HStack(spacing: TempoSpacing.sm) {
            // A 100 g "serving" is just the default, not a real one — offer
            // plain amounts instead of three chips that mean 50/100/200 anyway.
            if abs(unitGrams - 100) < 0.5 {
                ForEach([50.0, 100, 150, 200], id: \.self) { amount in
                    chip("\(Self.format(amount)) \(unitLabel)", grams: amount)
                }
            } else {
                chip("½ serving", grams: unitGrams * 0.5)
                chip("1 serving", grams: unitGrams)
                chip("2 servings", grams: unitGrams * 2)
                chip("100 \(unitLabel)", grams: 100)
            }
        }
    }

    private func chip(_ label: String, grams value: Double) -> some View {
        let selected = abs(grams - value) < 0.5
        return Button {
            grams = value
            gramsText = Self.format(value)
        } label: {
            Text(label)
                .font(.tempoCaption1)
                .foregroundStyle(selected ? Color.tempoTextInverse : Color.tempoTextPrimary)
                .lineLimit(1)
                .padding(.horizontal, TempoSpacing.md)
                .padding(.vertical, TempoSpacing.xs)
                .background(selected ? Color.tempoSignal : Color.tempoBgTertiary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Serving size with no parseable gram/ml amount (e.g. "1 slice") —
    /// falls back to a plain servings count instead of a grams field;
    /// `grams` here already IS that count (see `init`).
    private var servingsStepper: some View {
        Stepper(value: $grams, in: 0.5 ... 10, step: 0.5) {
            Text("\(Self.format(grams)) × \(item.servingSize)")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    private func save() {
        HapticManager.selection()
        var updated = item
        updated.servingQuantity = unitGrams > 0 ? grams / unitGrams : grams
        updated.calories = previewCalories
        updated.protein = densityProtein * grams
        updated.carbs = densityCarbs * grams
        updated.fat = densityFat * grams
        onSave(updated)
        dismiss()
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - ConfidenceLevel

enum ConfidenceLevel {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high: "Verified"
        case .medium: "Estimate"
        case .low: "Best guess"
        }
    }

    var color: Color {
        switch self {
        case .high: .tempoSuccess
        case .medium: .tempoWarning
        case .low: .tempoError
        }
    }

    var icon: String {
        switch self {
        case .high: "checkmark.circle.fill"
        case .medium: "exclamationmark.circle.fill"
        case .low: "questionmark.circle.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    MealLoggingView()
        .environment(ServiceContainer.mock())
        .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealLog.self], inMemory: true)
}

#Preview("With Items") {
    MealLoggingView(
        foodItems: [
            FoodItem(
                id: UUID(), name: "Chicken Breast", brand: nil,
                servingSize: "150g", servingQuantity: 1.0,
                calories: 248, protein: 46.0, carbs: 0.0, fat: 5.4
            ),
            FoodItem(
                id: UUID(), name: "Brown Rice", brand: nil,
                servingSize: "200g cooked", servingQuantity: 1.0,
                calories: 220, protein: 5.0, carbs: 46.0, fat: 1.8
            ),
            FoodItem(
                id: UUID(), name: "Greek Yogurt", brand: "Fage",
                servingSize: "170g", servingQuantity: 1.0,
                calories: 100, protein: 18.0, carbs: 6.0, fat: 0.7
            ),
        ]
    )
    .environment(ServiceContainer.mock())
    .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealLog.self], inMemory: true)
}
