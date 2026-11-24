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
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var selectedMealType: MealType = .init(EatenMealRecorder.defaultMealType())
    /// True between a successful save and the delayed dismiss, so a second
    /// tap can't log the same meal twice.
    @State
    private var didLog = false
    @State
    private var originPickedByHand = false
    @State
    private var origin: MealOrigin = HomeLocationStore().lastOrigin ?? .kitchen
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
            VStack(spacing: 0) {
                mealTypePicker
                mealScroll
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fuelBottomBar { stickyBottomBar }
            .tidePage()
            // A sheet is its own page, even when it comes up from inside one.
            .environment(\.tideInsidePage, false)
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .tideCovered(showFoodSearch || showVoiceLog || showPhotoAnalysis || showBarcodeScanner || editingItem != nil)
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
            .sensoryFeedback(.success, trigger: didLog) { _, new in new }
            .task {
                if catalog == nil {
                    catalog = FoodCatalog(services: services)
                }
            }
        }
    }

    // MARK: - Meal Type Picker

    /// Four answers with their symbols: the one picked lights up in the accent.
    private var mealTypePicker: some View {
        // Four across; two by two at accessibility sizes so no name is cut.
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Tide.s2),
            count: typeSize.isAccessibilitySize ? 2 : MealType.allCases.count
        )
        return LazyVGrid(columns: columns, spacing: Tide.s2) {
            ForEach(MealType.allCases) { type in
                let selected = selectedMealType == type
                Button {
                    selectedMealType = type
                } label: {
                    VStack(spacing: Tide.s1) {
                        Image(systemName: FuelMealStyle.icon(forName: type.rawValue))
                            .font(Tide.bodyStrong)
                            .accessibilityHidden(true)
                        Text(type.rawValue)
                            .font(Tide.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                    }
                    .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s2)
                    .fuelChoice(selected: selected, minHeight: Tide.hit + Tide.s2)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.vertical, Tide.s2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meal Type")
        .sensoryFeedback(.selection, trigger: selectedMealType)
    }

    // MARK: - Page

    /// The meal so far, then the ways to add to it. The numbers lead: they
    /// move as food comes in, so the page reads as a live total.
    private var mealScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                mealHero
                if foodItems.isEmpty {
                    emptyMethods
                } else {
                    TideSectionLabel(
                        title: "In this meal",
                        trailing: foodItems.count == 1 ? "1 item" : "\(foodItems.count) items"
                    )
                    VStack(spacing: 0) {
                        ForEach(foodItems) { item in
                            foodItemRow(item)
                            if item.id != foodItems.last?.id {
                                Divider().overlay(Tide.hairline)
                            }
                        }
                    }
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                    inputMethodButtons
                    originPicker
                        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
            .animation(Tide.snap, value: foodItems.isEmpty)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: - Hero

    private var mealHero: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber(
                    "\(totalCalories)", unit: "kcal", size: Tide.numeralL,
                    color: foodItems.isEmpty ? Tide.text3 : Tide.text
                )
                Spacer(minLength: Tide.s2)
                Text(selectedMealType.rawValue)
                    .tideLabel()
            }
            FuelMacroSplitBar(protein: Int(totalProtein), carbs: Int(totalCarbs), fat: Int(totalFat))
            if foodItems.isEmpty {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Nothing here yet. That's on you.")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Search, scan, or snap a photo to add food.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                FuelMacroInline(protein: Int(totalProtein), carbs: Int(totalCarbs), fat: Int(totalFat))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mealLog.hero")
    }

    /// Where the meal was eaten: only once there is something to place.
    private var originPicker: some View {
        MealOriginPicker(
            origin: $origin,
            foods: foodItems.map { EatenMealRecorder.plannedFood(from: $0.mealFoodInput) },
            pickedByHand: $originPickedByHand
        )
    }

    // MARK: - Ways to add (empty page)

    /// Four big doors into the meal, each with a line on what it does.
    private var emptyMethods: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Add food")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Tide.s3), GridItem(.flexible(), spacing: Tide.s3)],
                spacing: Tide.s3
            ) {
                methodTile(icon: "magnifyingglass", label: "Search", hint: "Type a food or brand") {
                    showFoodSearch = true
                }
                methodTile(icon: "camera.fill", label: "Photo", hint: "Snap your plate") {
                    showPhotoAnalysis = true
                }
                methodTile(icon: "barcode.viewfinder", label: "Scan", hint: "Read a barcode") {
                    showBarcodeScanner = true
                }
                methodTile(icon: "mic.fill", label: "Voice", hint: "Say what you ate") {
                    showVoiceLog = true
                }
            }
        }
    }

    private func methodTile(icon: String, label: String, hint: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.lightImpact()
            action()
        } label: {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideIconTile(systemName: icon)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(label)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text(hint)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s10, alignment: .topLeading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(FuelPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityIdentifier("mealLog.input.\(label.lowercased())")
    }

    // MARK: - Food Item Row

    private var itemRowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
    }

    private func foodItemRow(_ item: FoodItem) -> some View {
        HStack(spacing: Tide.s2) {
            // Tapping the row opens the portion editor — logged items used
            // to be locked to whatever grams they arrived with (picky-QA
            // item 4).
            Button {
                editingItem = item
            } label: {
                // Name and kcal side by side; the kcal drops under the name at
                // accessibility sizes so the name keeps the full width.
                itemRowLayout {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(item.name)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        Text(item.portionDescription)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        FuelMacroInline(protein: Int(item.protein), carbs: Int(item.carbs), fat: Int(item.fat))
                            .padding(.top, Tide.s1)
                    }

                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s2)
                    }

                    TideNumber("\(item.calories)", unit: "kcal", size: Tide.numeralS, relativeTo: .headline)
                }
                .frame(minHeight: Tide.hit + Tide.s3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mealItemRow")

            // Delete button
            Button {
                removeFoodItem(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text3)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.name)")
        }
    }

    // MARK: - Input Method Buttons

    private var inputMethodButtons: some View {
        GlassEffectContainer(spacing: Tide.s2) {
            // Four across; two by two at accessibility sizes.
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Tide.s2),
                    count: typeSize.isAccessibilitySize ? 2 : 4
                ),
                spacing: Tide.s2
            ) {
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
        }
    }

    private func inputMethodButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        FuelActionTile(icon: icon, label: label, identifier: "mealLog.input.\(label.lowercased())") {
            HapticManager.lightImpact()
            action()
        }
    }

    // MARK: - Sticky Bottom Bar

    private var stickyBottomBar: some View {
        Button {
            logMeal()
        } label: {
            // The total is already the hero; at accessibility sizes the bar
            // keeps just the verb so it stays one line and out of the way.
            Text(foodItems.isEmpty || typeSize.isAccessibilitySize ? "Log Meal" : "Log Meal · \(totalCalories) kcal")
                .contentTransition(.numericText())
        }
        .buttonStyle(.tidePrimary)
        .disabled(foodItems.isEmpty || didLog)
        .accessibilityLabel("Log Meal")
        .accessibilityValue(foodItems.isEmpty ? "" : "\(totalCalories) kilocalories")
        .animation(Tide.snap, value: totalCalories)
    }

    // MARK: - Actions

    private func addFoodItem(_ item: FoodItem) {
        withAnimation(Tide.snap) {
            foodItems.append(item)
        }
        HapticManager.lightImpact()
    }

    private func removeFoodItem(_ item: FoodItem) {
        withAnimation(Tide.snap) {
            foodItems.removeAll { $0.id == item.id }
        }
        HapticManager.lightImpact()
    }

    /// Replaces a logged item with its re-portioned version and remembers
    /// the chosen grams for next time this product gets added.
    private func updateFoodItem(_ updated: FoodItem) {
        withAnimation(Tide.snap) {
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
                origin: origin,
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
        HomeLocationStore().lastOrigin = origin
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
    @Environment(\.tideMood)
    private var mood

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
            VStack(spacing: Tide.s5) {
                VStack(spacing: Tide.hair) {
                    Text(item.name)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                    if let brand = item.brand {
                        Text(brand)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                }
                .padding(.top, Tide.s4)

                if unitGrams > 0 {
                    gramsField
                    quickChips
                } else {
                    servingsStepper
                }

                VStack(spacing: Tide.s2) {
                    TideNumber("\(previewCalories)", unit: "kcal", size: Tide.numeralL)
                    FuelMacroInline(
                        protein: Int((densityProtein * grams).rounded()),
                        carbs: Int((densityCarbs * grams).rounded()),
                        fat: Int((densityFat * grams).rounded())
                    )
                }

                Spacer(minLength: 0)

                Button {
                    save()
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tidePrimary)
                .disabled(grams <= 0)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s4)
            .tidePage()
            .navigationTitle("Edit portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var gramsField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
            TextField(unitLabel, text: $gramsText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Tide.numeral(Tide.numeralM))
                .foregroundStyle(Tide.text)
                .frame(width: Tide.s10 * 3)
                .accessibilityIdentifier("portionEditorGrams")
                .onChange(of: gramsText) { _, text in
                    if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0, value <= 5000 {
                        grams = value
                    }
                }
            Text(unitLabel)
                .font(Tide.headline)
                .foregroundStyle(Tide.text2)
        }
        .fuelField(radius: Tide.tileRadius)
    }

    private var quickChips: some View {
        ViewThatFits(in: .horizontal) {
            chipRow
            // Four labels do not fit one line at large text sizes.
            VStack(spacing: Tide.s2) { chipRow }
        }
    }

    private var chipRow: some View {
        HStack(spacing: Tide.s2) {
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
                .font(Tide.caption)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .fuelChip(selected: selected)
        }
        .buttonStyle(FuelPressStyle())
        .sensoryFeedback(.selection, trigger: selected)
    }

    /// Serving size with no parseable gram/ml amount (e.g. "1 slice") —
    /// falls back to a plain servings count instead of a grams field;
    /// `grams` here already IS that count (see `init`).
    private var servingsStepper: some View {
        Stepper(value: $grams, in: 0.5 ... 10, step: 0.5) {
            Text("\(Self.format(grams)) × \(item.servingSize)")
                .font(Tide.body)
                .foregroundStyle(Tide.text)
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
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
        case .high: Tide.good
        case .medium: Tide.warn
        case .low: Tide.danger
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
