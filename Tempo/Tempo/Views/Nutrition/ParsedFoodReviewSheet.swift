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

struct ParsedFoodReviewSheet: View {
    let items: [ParsedFoodItem]
    let onConfirm: ([ParsedFoodItem], MealType, Date, MealOrigin) -> Void
    let onCancel: () -> Void

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
        onConfirm: @escaping ([ParsedFoodItem], MealType, Date, MealOrigin) -> Void,
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
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    summaryCard
                    whenCard
                    originCard(pantry: pantry)
                    foodsCard(pantry: pantry)
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.sm)
                .padding(.bottom, TempoSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.tempoBgPrimary)
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
            .safeAreaInset(edge: .bottom, spacing: 0) { logBar }
            .task { await refreshOrigin() }
            .sheet(isPresented: $showHomeSetting, onDismiss: { Task { await refreshOrigin() } }) {
                HomeLocationSettingView()
            }
        }
    }

    // MARK: - Primary action

    private var logBar: some View {
        Button(action: confirm) {
            Text(draft.items.isEmpty ? "Nothing to log" : "Log \(draft.totalCalories) kcal")
                .font(.tempoHeadline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Color.tempoInk)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(draft.items.isEmpty || didConfirm ? Color.tempoTextDisabled : Color.tempoSignal)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(didConfirm || draft.items.isEmpty)
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.md)
        .padding(.bottom, TempoSpacing.sm)
        .background(.bar)
        .animation(.snappy, value: draft.totalCalories)
        .accessibilityIdentifier("reviewLog")
        .accessibilityLabel(draft.items.isEmpty ? "Nothing to log" : "Log \(draft.totalCalories) kilocalories")
    }

    private func confirm() {
        guard !didConfirm, !draft.items.isEmpty else {
            return
        }
        didConfirm = true
        HapticManager.success()
        HomeLocationStore().lastOrigin = draft.origin
        onConfirm(draft.items, draft.mealType, draft.eatenAt, draft.origin)
        dismiss()
    }

    // MARK: - Summary (the answer first)

    private var summaryCard: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                Text("\(draft.totalCalories)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("kcal")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .minimumScaleFactor(0.6)
            HStack(spacing: TempoSpacing.xl) {
                macro("P", Int(draft.totalProtein), Color.tempoMacroProtein)
                macro("C", Int(draft.totalCarbs), Color.tempoMacroCarbs)
                macro("F", Int(draft.totalFat), Color.tempoMacroFat)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.lg)
        .background(Color.tempoBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .animation(.snappy, value: draft.totalCalories)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Total \(draft.totalCalories) kilocalories. Protein \(Int(draft.totalProtein)) grams, carbs \(Int(draft.totalCarbs)) grams, fat \(Int(draft.totalFat)) grams."
        )
        .accessibilityIdentifier("reviewTotal")
    }

    private func macro(_ letter: String, _ grams: Int, _ color: Color) -> some View {
        HStack(spacing: TempoSpacing.xs) {
            Text(letter).foregroundStyle(color).fontWeight(.semibold)
            Text("\(grams)g").foregroundStyle(Color.tempoTextPrimary)
                .contentTransition(.numericText())
        }
        .font(.tempoCallout.monospacedDigit())
    }

    // MARK: - When

    private var whenCard: some View {
        card("WHEN") {
            HStack {
                Text(Self.relativeDay(draft.eatenAt))
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
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
            .frame(minHeight: 44)
            HStack(spacing: TempoSpacing.sm) {
                ForEach(MealType.allCases, id: \.self) { type in
                    mealChip(type)
                }
            }
            .accessibilityIdentifier("reviewMealType")
        }
    }

    private func mealChip(_ type: MealType) -> some View {
        let selected = draft.mealType == type
        return Button {
            HapticManager.selection()
            withAnimation(.snappy) { draft.setMealType(type) }
        } label: {
            VStack(spacing: TempoSpacing.xs) {
                Image(systemName: type.icon)
                    .font(.system(size: 18))
                Text(type.displayName)
                    .font(.tempoCaption1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.tempoInk : Color.tempoTextPrimary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? Color.tempoSignal : Color.tempoBgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
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
            HStack(spacing: TempoSpacing.sm) {
                originChoice(.kitchen, icon: "house.fill", title: "Kitchen")
                originChoice(.out, icon: "fork.knife", title: "Ate out")
            }
            .accessibilityIdentifier("reviewOrigin")
            if draft.origin == .mixed {
                Label("Mixed: some from home, some out", systemImage: "arrow.triangle.branch")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .accessibilityIdentifier("reviewOriginMixed")
            }
            if let originHeadline {
                Text(originHeadline)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
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
                .font(.tempoCallout.weight(.semibold))
                .foregroundStyle(selected ? Color.tempoInk : Color.tempoTextPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? Color.tempoSignal : Color.tempoBgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
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
                draft.origin == .out ? "Nothing from home. Your pantry stays as it is." : "Nothing from home. Nothing comes off your pantry.",
                systemImage: "checkmark.circle"
            )
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("reviewOriginPreview")
        } else {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text("Comes off your pantry")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                FlowLayout(spacing: TempoSpacing.sm, lineSpacing: TempoSpacing.sm) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text("\(line.displayName) \(line.amountText)")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .padding(.horizontal, TempoSpacing.md)
                            .padding(.vertical, TempoSpacing.xs + 2)
                            .background(Color.tempoBgTertiary)
                            .clipShape(Capsule())
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
                .font(.tempoCaption1.weight(.semibold))
                .foregroundStyle(home == nil ? Color.tempoSignal : Color.tempoTextSecondary)
                .padding(.horizontal, TempoSpacing.md)
                .frame(minHeight: 44)
                .background(Color.tempoBgTertiary)
                .clipShape(Capsule())
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
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(minHeight: 44, alignment: .leading)
            } else {
                Text("Mark what came from your kitchen. Only those come off your pantry.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                VStack(spacing: 0) {
                    let visible = items.filter { draft.factors[$0.id] != nil }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().overlay(Color.tempoDivider).padding(.vertical, TempoSpacing.sm)
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
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(original.name.capitalizedFirst)
                        .font(.tempoBodyBold)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(current.formattedPortion)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer(minLength: TempoSpacing.sm)
                Text("\(Int(current.calories)) kcal")
                    .font(.tempoCallout.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            if current.isBigPortion {
                Label("That's a big one. Check the portion.", systemImage: "exclamationmark.circle.fill")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoWarning)
                    .accessibilityIdentifier("reviewBigPortion")
            }
            if fromKitchen, !pantryLines.isEmpty {
                Text("Off pantry: " + pantryLines.map { "\($0.displayName) \($0.amountText)" }.joined(separator: ", "))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: TempoSpacing.sm) {
                ForEach(MealReviewDraft.factorChoices, id: \.self) { choice in
                    chip(choice, for: original)
                }
            }
            HStack(spacing: TempoSpacing.sm) {
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
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
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
                .font(.tempoCallout.weight(.semibold))
                .foregroundStyle(selected ? Color.tempoInk : Color.tempoTextPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.tempoSignal : Color.tempoBgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
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
                .font(.tempoCaption1.weight(.semibold))
                .foregroundStyle(fromKitchen ? Color.tempoSignal : Color.tempoTextSecondary)
                .padding(.horizontal, TempoSpacing.md)
                .frame(minHeight: 44)
                .background(fromKitchen ? Color.tempoSignal.opacity(0.16) : Color.tempoBgTertiary)
                .clipShape(Capsule())
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
                .font(.tempoCaption1)
                .foregroundStyle(open ? Color.tempoSignal : Color.tempoTextSecondary)
                .padding(.horizontal, TempoSpacing.sm)
                .frame(minHeight: 44)
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
                .font(.system(size: 20))
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(original.name)")
    }

    private func gramsField(_ original: ParsedFoodItem, current: ParsedFoodItem) -> some View {
        HStack(spacing: 2) {
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
            .font(.tempoCallout.monospacedDigit())
            .frame(width: 56)
            Text("g")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.horizontal, TempoSpacing.md)
        .frame(minHeight: 44)
        .background(Color.tempoBgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text(title)
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.lg)
        .background(Color.tempoBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
