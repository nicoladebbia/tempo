//
// ParsedFoodReviewSheet.swift
// Tempo
//
// The confirmation step between "the app worked out what you ate" and "it's
// saved": Quick Log text, a meal photo and a barcode all land here. Nothing is
// written before the single primary button at the bottom.
//
// Layout (top to bottom): the answer first (total kcal + macros, animated),
// then three chunks: WHEN (time + meal chips) · WHERE FROM (kitchen / ate out,
// what comes off the pantry) · WHAT YOU ATE (a row per food: portion chips,
// a house toggle for "this one is from my kitchen", exact grams on expand).
//

import CoreLocation
import SwiftData
import SwiftUI

// MARK: - ParsedFoodReviewSheet

struct ParsedFoodReviewSheet: View {
    let items: [ParsedFoodItem]
    /// Saves the meal. Returns why it could not be saved, or nil when it was (or when
    /// the caller has taken over, as for a repeat question): the sheet closes only then.
    let onConfirm: ([ParsedFoodItem], MealType, Date, MealOrigin) -> String?
    let onCancel: () -> Void

    @Environment(\.tideMood)
    private var mood
    @State
    private var draft: MealReviewDraft
    /// Grams text per row while the user is typing; committed on every valid keystroke.
    @State
    private var gramsText: [String: String] = [:]
    /// Rows whose exact-grams field is open (progressive disclosure).
    @State
    private var expanded: Set<String> = []
    /// Set on the first Log tap so a double-tap can't log the meal twice.
    @State
    private var didConfirm = false
    /// Why the last Log tap did not save. The sheet stays open, with the meal as it was typed.
    @State
    private var saveError: String?

    /// nil = no fix / no home / too imprecise. Set by the fix started in `.task`.
    @State
    private var atHome: Bool?
    @State
    private var home: HomeLocation? = HomeLocationStore().home
    @State
    private var showHomeSetting = false

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.locationFixProvider)
    private var locationProvider

    init(
        items: [ParsedFoodItem],
        hintedMealType: MealType?,
        hintedDate: Date?,
        onConfirm: @escaping ([ParsedFoodItem], MealType, Date, MealOrigin) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.items = items
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _draft = State(initialValue: MealReviewDraft(items: items, hintedDate: hintedDate, hintedType: hintedMealType))
    }

    var body: some View {
        let pantry = pantryByItem
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    summaryCard
                    whenCard
                    originCard(pantry: pantry)
                    foodsCard(pantry: pantry)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .fuelBottomBar { logBar }
            .tidePage()
            .navigationTitle("Confirm meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .accessibilityIdentifier("reviewCancel")
                }
            }
            .task { await refreshOrigin() }
            .sheet(isPresented: $showHomeSetting, onDismiss: { Task { await refreshOrigin() } }) {
                HomeLocationSettingView()
            }
        }
    }

    // MARK: - Primary action

    private var logBar: some View {
        VStack(spacing: Tide.s3) {
            if let saveError {
                // On the sheet itself: a toast behind it would never be seen.
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reviewSaveError")
            }
            Button(action: confirm) {
                Text(draft.items.isEmpty ? "Nothing to log" : "Log \(draft.totalCalories) kcal")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .buttonStyle(.tidePrimary)
            .disabled(didConfirm || draft.items.isEmpty)
            .animation(Tide.snap, value: draft.totalCalories)
            .accessibilityIdentifier("reviewLog")
            .accessibilityLabel(draft.items.isEmpty ? "Nothing to log" : "Log \(draft.totalCalories) kilocalories")
        }
        .animation(Tide.snap, value: saveError)
    }

    private func confirm() {
        guard !didConfirm, !draft.items.isEmpty else {
            return
        }
        didConfirm = true
        saveError = nil
        HomeLocationStore().lastOrigin = draft.origin
        if let failure = onConfirm(draft.items, draft.mealType, draft.eatenAt, draft.origin) {
            // Not saved: stay open so nothing typed is lost, and let the next tap try again.
            didConfirm = false
            saveError = failure
            HapticManager.notification(.error)
            return
        }
        HapticManager.success()
        dismiss()
    }

    // MARK: - Summary (the answer first)

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideNumber("\(draft.totalCalories)", unit: "kcal", size: Tide.numeralL, relativeTo: .largeTitle)
            FuelMacroRings(
                protein: Int(draft.totalProtein.rounded()), carbs: Int(draft.totalCarbs.rounded()), fat: Int(draft.totalFat.rounded())
            )
        }
        .tideCard()
        .animation(Tide.snap, value: draft.totalCalories)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Total \(draft.totalCalories) kilocalories. Protein \(Int(draft.totalProtein.rounded())) grams, carbs \(Int(draft.totalCarbs.rounded())) grams, fat \(Int(draft.totalFat.rounded())) grams."
        )
        .accessibilityIdentifier("reviewTotal")
    }

    // MARK: - When

    private var whenCard: some View {
        card("WHEN") {
            HStack {
                Text(Self.relativeDay(draft.eatenAt))
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                Spacer()
                DatePicker(
                    "Time eaten",
                    selection: Binding(get: { draft.eatenAt }, set: { draft.setEatenAt($0) }),
                    in: ...Date().addingTimeInterval(60),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .accessibilityIdentifier("reviewTime")
            }
            .frame(minHeight: Tide.hit)
            mealChipRow
                .accessibilityIdentifier("reviewMealType")
        }
    }

    /// The meal types side by side, in two rows at accessibility text sizes.
    private var mealChipRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s2) {
                ForEach(MealType.allCases, id: \.self) { type in
                    mealChip(type)
                }
            }
            VStack(spacing: Tide.s2) {
                ForEach(MealType.allCases, id: \.self) { type in
                    mealChip(type)
                }
            }
        }
    }

    private func mealChip(_ type: MealType) -> some View {
        let selected = draft.mealType == type
        return Button {
            HapticManager.selection()
            withAnimation(.snappy) { draft.setMealType(type) }
        } label: {
            VStack(spacing: Tide.s1) {
                Image(systemName: type.icon)
                    .font(Tide.headline)
                Text(type.displayName)
                    .font(Tide.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .frame(maxWidth: .infinity)
            .fuelChoice(selected: selected, minHeight: Tide.hit + Tide.s3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }

    // MARK: - Where from

    private func originCard(pantry: [String: [PantryPreviewLine]]) -> some View {
        card("WHERE FROM") {
            HStack(spacing: Tide.s2) {
                originChoice(.kitchen, icon: "house.fill", title: "Kitchen")
                originChoice(.out, icon: "fork.knife", title: "Ate out")
            }
            .accessibilityIdentifier("reviewOrigin")
            if draft.origin == .mixed {
                Label("Mixed: some from home, some out", systemImage: "arrow.triangle.branch")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .accessibilityIdentifier("reviewOriginMixed")
            }
            if let originHeadline {
                Text(originHeadline)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .accessibilityIdentifier("reviewOriginHeadline")
            }
            pantryStatus(pantry: pantry)
            homeChip
        }
    }

    private func originChoice(_ choice: MealOrigin, icon: String, title: String) -> some View {
        let selected = draft.origin == choice
        return Button {
            HapticManager.selection()
            withAnimation(.snappy) { draft.setOrigin(choice) }
        } label: {
            Label(title, systemImage: icon)
                .font(Tide.bodyStrong)
                .frame(maxWidth: .infinity)
                .fuelChoice(selected: selected, minHeight: Tide.hit + Tide.s1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// "Comes off your pantry" + a chip per item, or a neutral "Nothing from home".
    @ViewBuilder
    private func pantryStatus(pantry: [String: [PantryPreviewLine]]) -> some View {
        let lines = draft.items.flatMap { pantry[$0.id] ?? [] }
        if lines.isEmpty {
            Label(
                draft
                    .origin == .out ? "Nothing from home. Your pantry stays as it is." :
                    "Nothing from home. Nothing comes off your pantry.",
                systemImage: "checkmark.circle"
            )
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("reviewOriginPreview")
        } else {
            VStack(alignment: .leading, spacing: Tide.s2) {
                Text("Comes off your pantry")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text("\(line.displayName) \(line.amountText)")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text)
                            .padding(.horizontal, Tide.s3)
                            .padding(.vertical, Tide.s2)
                            .background(Tide.fill, in: Capsule())
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Comes off your pantry: " + lines.map { "\($0.displayName) \($0.amountText)" }.joined(separator: ", "))
            .accessibilityIdentifier("reviewOriginPreview")
        }
    }

    private var homeChip: some View {
        Button {
            showHomeSetting = true
        } label: {
            Label(home == nil ? "Set home" : "Home: set", systemImage: home == nil ? "house" : "house.fill")
                .font(Tide.caption)
                .fuelChip(selected: home == nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(home == nil ? "Set home location" : "Home is set. Change home location")
        .accessibilityIdentifier("reviewSetHome")
    }

    private var originHeadline: String? {
        guard home != nil, draft.origin != .mixed else {
            return nil
        }
        switch atHome {
        case true?: return draft.origin == .kitchen ? "You're home. From your kitchen?" : "You're home. Logged as eaten out."
        case false?: return draft.origin == .out ? "Not home. Logged as eaten out." : "Not home, but from your kitchen."
        case nil: return "Can't tell where you are. Using your last choice."
        }
    }

    /// Reads the saved home and (only when location is already granted) one
    /// fix, then pre-selects Kitchen / Ate out. Never prompts.
    private func refreshOrigin() async {
        let store = HomeLocationStore()
        home = store.home
        var fix: CLLocation?
        if home != nil {
            fix = await locationProvider.fixIfAuthorized(timeout: 3)
        }
        atHome = HomeAwayDecider.isAtHome(fix: fix, home: home)
        draft.applySuggestedOrigin(HomeAwayDecider.defaultOrigin(atHome: atHome, remembered: store.lastOrigin))
    }

    /// What each food that is marked "from my kitchen" would take off the
    /// pantry, by food id (dry run: nothing is changed).
    private var pantryByItem: [String: [PantryPreviewLine]] {
        let kitchen = draft.items.filter { draft.origin(for: $0.id) == .kitchen }
        guard !kitchen.isEmpty else {
            return [:]
        }
        let foods = kitchen.map {
            PlannedFood(
                name: $0.name, quantityGrams: $0.quantityGrams,
                calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG
            )
        }
        let perFood = PantryDecrementService.previewByFood(foods: foods, modelContext: modelContext)
        var result: [String: [PantryPreviewLine]] = [:]
        for (index, item) in kitchen.enumerated() where index < perFood.count && !perFood[index].isEmpty {
            result[item.id] = perFood[index]
        }
        return result
    }

    // MARK: - Foods

    private func foodsCard(pantry: [String: [PantryPreviewLine]]) -> some View {
        card("WHAT YOU ATE") {
            if draft.items.isEmpty {
                Text("Nothing left to log.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .frame(minHeight: 44, alignment: .leading)
            } else {
                Text("Mark what came from your kitchen. Only those come off your pantry.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                VStack(spacing: 0) {
                    let visible = items.filter { draft.factors[$0.id] != nil }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().overlay(Tide.hairline).padding(.vertical, Tide.s2)
                        }
                        row(item, pantryLines: pantry[item.id] ?? [])
                    }
                }
            }
        }
    }

    private func row(_ original: ParsedFoodItem, pantryLines: [PantryPreviewLine]) -> some View {
        let current = original.scaled(by: draft.factor(for: original.id))
        let fromKitchen = draft.origin(for: original.id) == .kitchen
        return VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(original.name.capitalizedFirst)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                    Text(current.formattedPortion)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                Spacer(minLength: Tide.s2)
                Text("\(Int(current.calories.rounded())) kcal")
                    .font(Tide.body.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(Tide.text)
            }
            if current.isBigPortion {
                Label("That's a big one. Check the portion.", systemImage: "exclamationmark.circle.fill")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.warn)
                    .accessibilityIdentifier("reviewBigPortion")
            }
            if fromKitchen, !pantryLines.isEmpty {
                Text("Off pantry: " + pantryLines.map { "\($0.displayName) \($0.amountText)" }.joined(separator: ", "))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Tide.s2) {
                ForEach(MealReviewDraft.factorChoices, id: \.self) { choice in
                    chip(choice, for: original)
                }
            }
            HStack(spacing: Tide.s2) {
                homeToggle(original, fromKitchen: fromKitchen)
                Spacer(minLength: 0)
                if original.quantityGrams > 0 {
                    expandButton(original)
                }
                removeButton(original)
            }
            if expanded.contains(original.id), original.quantityGrams > 0 {
                HStack {
                    Text("Exact weight")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                    Spacer()
                    gramsField(original, current: current)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ choice: Double, for original: ParsedFoodItem) -> some View {
        let selected = abs(draft.factor(for: original.id) - choice) < 0.001
        return Button {
            HapticManager.lightImpact()
            withAnimation(.snappy) { draft.setFactor(choice, for: original.id) }
            gramsText[original.id] = nil
        } label: {
            Text(Self.chipLabel(choice))
                .font(Tide.bodyStrong)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .frame(maxWidth: .infinity)
                .fuelChoice(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.chipLabel(choice)) portion of \(original.name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func homeToggle(_ original: ParsedFoodItem, fromKitchen: Bool) -> some View {
        Button {
            HapticManager.selection()
            withAnimation(.snappy) { draft.setOrigin(fromKitchen ? .out : .kitchen, for: original.id) }
        } label: {
            Label("From my kitchen", systemImage: fromKitchen ? "house.fill" : "house")
                .font(Tide.caption)
                .fuelChip(selected: fromKitchen)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(original.name) from my kitchen")
        .accessibilityValue(fromKitchen ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    private func expandButton(_ original: ParsedFoodItem) -> some View {
        let open = expanded.contains(original.id)
        return Button {
            withAnimation(.snappy) {
                if open {
                    expanded.remove(original.id)
                } else {
                    expanded.insert(original.id)
                }
            }
        } label: {
            Label("Grams", systemImage: "scalemass")
                .font(Tide.caption)
                .foregroundStyle(open ? mood.accent : Tide.text2)
                .padding(.horizontal, Tide.s2)
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(open ? "Hide exact weight" : "Set exact weight for \(original.name)")
    }

    private func removeButton(_ original: ParsedFoodItem) -> some View {
        Button {
            HapticManager.lightImpact()
            withAnimation(.snappy) { draft.remove(original.id) }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(Tide.title2)
                .foregroundStyle(Tide.text3)
                .frame(width: Tide.hit, height: Tide.hit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(original.name)")
    }

    private func gramsField(_ original: ParsedFoodItem, current: ParsedFoodItem) -> some View {
        HStack(spacing: Tide.hair) {
            TextField(
                "g",
                text: Binding(
                    get: { gramsText[original.id] ?? String(Int(current.quantityGrams.rounded())) },
                    set: { text in
                        gramsText[original.id] = text
                        if let grams = Double(text.replacingOccurrences(of: ",", with: ".")) {
                            draft.setGrams(grams, for: original.id)
                            if draft.factor(for: original.id) >= MealReviewDraft.maxFactor {
                                gramsText[original.id] = nil // capped: show the real figure
                            }
                        }
                    }
                )
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(Tide.body.monospacedDigit())
            .frame(width: Tide.fuelAmountField)
            Text("g")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
        }
        .fuelField()
    }

    static func chipLabel(_ factor: Double) -> String {
        switch factor {
        case 0.5: "½"
        case 1.5: "1½"
        default: factor == factor.rounded() ? "\(Int(factor))" : String(factor)
        }
    }

    // MARK: - Card chrome

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        FuelSection(title: title) {
            content()
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
