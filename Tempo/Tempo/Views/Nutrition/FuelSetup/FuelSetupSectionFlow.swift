//
// FuelSetupSectionFlow.swift
// Tempo
//
// One section of the Fuel setup as an onboarding-style flow: a screen per
// small group of related questions, compact tappable answers, progress dots,
// Back / Next, and a Save on the last screen that writes ONLY this section.
// Optional questions have a Skip; once something changed, "Save & close" in
// the top bar saves without paging to the end. In a "Finish setup" chain the
// last button reads "Save & next: <section>" and saves each section as it
// goes. Edits happen on a working copy, so closing the flow throws them away.
//

import SwiftUI

struct FuelSetupSectionFlow: View {
    let section: FuelSetupSection
    /// Locked (Apple Health) body stats for the "You" section.
    var locked: Set<FuelBodyField> = []
    var unit: WeightUnit = .kg
    /// Saves the edited copy of this section (async: places are located first).
    var onSave: (FuelSetupDraft) async -> Void
    var onClose: () -> Void
    /// Inside a "Finish setup" chain: the section that follows this one
    /// (nil on the last), and whether this is a chain at all.
    var isChain = false
    var chainNext: FuelSetupSection?
    /// Leaves an OPTIONAL section without saving (chain only).
    var onSkipSection: (() -> Void)?

    /// The draft as the flow opened, to tell whether anything changed.
    private let original: FuelSetupDraft

    @State
    private var working: FuelSetupDraft
    @State
    private var index = 0
    /// The answers as this screen opened: Skip puts them back, so a default a
    /// stepper wrote on appear (or a half-typed value) is never kept.
    @State
    private var entry: FuelSetupDraft?
    @State
    private var isSaving = false
    @Environment(\.tideMood)
    private var mood

    init(
        section: FuelSetupSection,
        draft: FuelSetupDraft,
        locked: Set<FuelBodyField> = [],
        unit: WeightUnit = .kg,
        isChain: Bool = false,
        chainNext: FuelSetupSection? = nil,
        onSkipSection: (() -> Void)? = nil,
        onSave: @escaping (FuelSetupDraft) async -> Void,
        onClose: @escaping () -> Void
    ) {
        self.section = section
        self.locked = locked
        self.unit = unit
        self.isChain = isChain
        self.chainNext = chainNext
        self.onSkipSection = onSkipSection
        self.onSave = onSave
        self.onClose = onClose
        original = draft
        _working = State(initialValue: draft)
    }

    private var steps: [FuelFlowStep] {
        let steps = FuelFlowStep.steps(for: section, draft: working, locked: locked)
        return steps.isEmpty ? [.healthBody] : steps
    }

    private var step: FuelFlowStep {
        steps[min(index, steps.count - 1)]
    }

    private var isDirty: Bool {
        working.isDirty(section, comparedTo: original)
    }

    private var allStepsValid: Bool {
        steps.allSatisfy { $0.isValid(in: working, locked: locked) }
    }

    private var lastTitle: String {
        if let chainNext {
            return String(localized: "Save & next: \(chainNext.title)")
        }
        return isChain ? String(localized: "Save & finish") : String(localized: "Save")
    }

    private var skipAction: (() -> Void)? {
        step.isOptional ? { skip() } : nil
    }

    private var saveCloseAction: (() -> Void)? {
        isDirty ? { save() } : nil
    }

    private var skipSectionAction: (() -> Void)? {
        isChain && !section.isRequired ? onSkipSection : nil
    }

    var body: some View {
        FuelFlowScaffold(
            eyebrow: section.title,
            title: Self.title(for: step),
            subtitle: Self.subtitle(for: step),
            index: min(index, steps.count - 1),
            count: steps.count,
            canContinue: step.isValid(in: working, locked: locked),
            isSaving: isSaving,
            isLast: index >= steps.count - 1,
            lastTitle: lastTitle,
            onSkip: skipAction,
            onSaveAndClose: saveCloseAction,
            canSaveAndClose: allStepsValid,
            onSkipSection: skipSectionAction,
            onBack: { entry = working; withAnimation(Tide.snap) { index = max(0, index - 1) } },
            onNext: next,
            onClose: onClose
        ) {
            stepContent
        }
        .id(step)
        .transition(.opacity)
        // The field sits outside the per-step identity, so it stays put while the questions cross-fade.
        .tidePage()
    }

    private func next() {
        KeyboardDismisser.dismiss()
        if index < steps.count - 1 {
            entry = working
            withAnimation(Tide.snap) { index += 1 }
            return
        }
        save()
    }

    /// Leaves this question as it is (optional questions only).
    private func skip() {
        KeyboardDismisser.dismiss()
        working = entry ?? original
        if index < steps.count - 1 {
            entry = working
            withAnimation(Tide.snap) { index += 1 }
        } else {
            save()
        }
    }

    private func save() {
        KeyboardDismisser.dismiss()
        guard !isSaving else {
            return
        }
        isSaving = true
        Task {
            await onSave(working)
            isSaving = false
        }
    }

    // MARK: - Copy

    static func title(for step: FuelFlowStep) -> String {
        switch step {
        case .healthBody: String(localized: "Your body")
        case .bodyStats: String(localized: "About you")
        case .sex: String(localized: "Male or female?")
        case .bodyFat: String(localized: "Body fat?")
        case .goal: String(localized: "What's the goal?")
        case .goalTarget: String(localized: "Where to?")
        case .trainingDays: String(localized: "Training days a week")
        case .meals: String(localized: "Meals a day")
        case .window: String(localized: "Eating window")
        case .weekDays: String(localized: "Your week")
        case .places: String(localized: "Where you eat")
        case .notes: String(localized: "Anything else?")
        case .restrictions: String(localized: "Diet rules and allergies")
        case .wontEat: String(localized: "Never serve me")
        case .favourites: String(localized: "Foods you love")
        case .tastes: String(localized: "Your taste")
        case .appetite: String(localized: "Snacks and portions")
        case .skill: String(localized: "How good are you in the kitchen?")
        case .cookTimes: String(localized: "Cooking time")
        case .leftovers: String(localized: "Leftovers")
        case .equipment: String(localized: "What's in your kitchen?")
        case .clearSkin: String(localized: "Clear-skin focus")
        case .shopping: String(localized: "Budget and stores")
        case .recovery: String(localized: "Recovery-adjusted meals")
        }
    }

    static func subtitle(for step: FuelFlowStep) -> String? {
        switch step {
        case .healthBody: String(localized: "Straight from Apple Health. Change it there, not here.")
        case .bodyStats: String(localized: "For your calorie and protein targets.")
        case .sex: String(localized: "Biological sex, for the calorie formula.")
        case .bodyFat: String(localized: "Optional. Skip it if you don't know.")
        case .goal: String(localized: "Pick one. The plan is built around it.")
        case .goalTarget: String(localized: "Your target weight and how fast.")
        case .trainingDays: String(localized: "Fuel follows the days you train.")
        case .meals: String(localized: "Including the snacks you plan.")
        case .window: String(localized: "First and last meal. The plan fits inside it.")
        case .weekDays: String(localized: "Tap a day: wake-up, classes or work, training.")
        case .places: String(localized: "Campus, work, gym. We look up restaurants nearby.")
        case .notes: String(localized: "Anything the planner should know.")
        case .restrictions: String(localized: "Tap all that apply. None is fine. Allergies are never in your plan.")
        case .wontEat: String(localized: "Never-foods are permanent. Sick-of foods rotate down for a while.")
        case .favourites: String(localized: "These show up more often.")
        case .tastes: String(localized: "Tap again to clear. No pick means no preference.")
        case .appetite: String(localized: "The daily macros stay the same. This shapes the meals.")
        case .skill: String(localized: "Sets how complex the recipes get.")
        case .cookTimes: String(localized: "Days you cook, and minutes for one meal. The rest of the week is quick or leftovers.")
        case .leftovers: String(localized: "How you feel about eating the same meal again.")
        case .equipment: String(localized: "The planner only programs recipes you can make.")
        case .clearSkin: String(localized: "Low-GI carbs, no added sweeteners, minimal dairy. Macros stay the same.")
        case .shopping: String(localized: "The grocery list stays under your budget.")
        case .recovery: String(localized: "More carbs on training days, lighter on rest days, using your recovery data.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .healthBody: healthBody
        case .bodyStats: bodyStats
        case .sex:
            choiceStack {
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    FuelChoiceCard(
                        title: sex.displayName,
                        icon: sex == .male ? "figure.stand" : "figure.stand.dress",
                        isSelected: working.sex == sex
                    ) {
                        working.sex = sex
                    }
                }
            }
        case .bodyFat:
            FuelNumberField(value: $working.bodyFatPercent, unit: "%", id: "fuelBodyFat")
        case .goal: goalChoices
        case .goalTarget: goalTarget
        case .trainingDays:
            FuelBigStepper(
                value: $working.trainingDaysPerWeek,
                defaultValue: max(working.routine.trainingDaysPerWeek, 3),
                range: 0 ... 7,
                unit: String(localized: "days"),
                id: "fuelTrainingDays"
            )
        case .meals:
            choiceStack {
                FuelBigStepper(
                    value: $working.mealsPerDay,
                    defaultValue: 4,
                    range: 1 ... 8,
                    unit: String(localized: "meals"),
                    label: String(localized: "Meals a day"),
                    id: "fuelMeals"
                )
                FuelChoiceCard(
                    title: String(localized: "I eat breakfast"),
                    subtitle: String(localized: "First meal in the morning"),
                    icon: "sunrise.fill",
                    isSelected: working.breakfastSkipped == false
                ) {
                    working.breakfastSkipped = false
                }
                FuelChoiceCard(
                    title: String(localized: "I skip it"),
                    subtitle: String(localized: "First meal comes later"),
                    icon: "moon.zzz.fill",
                    isSelected: working.breakfastSkipped == true
                ) {
                    working.breakfastSkipped = true
                }
            }
        case .window: windowPicker
        case .weekDays: weekDays
        case .places: places
        case .notes:
            TextField("Notes for your planner", text: $working.notes, axis: .vertical)
                .font(Tide.body)
                .lineLimit(4 ... 10)
                .padding(Tide.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
        case .restrictions:
            VStack(alignment: .leading, spacing: Tide.s4) {
                restrictions
                sectionLabel(String(localized: "Allergies"))
                FuelChipListInput(
                    values: $working.allergies, placeholder: String(localized: "Peanuts, shellfish…"),
                    suggestions: ["Peanuts", "Tree nuts", "Shellfish", "Eggs", "Soy"], id: "fuelAllergies"
                )
            }
        case .wontEat:
            VStack(alignment: .leading, spacing: Tide.s4) {
                sectionLabel(String(localized: "Never serve me"))
                FuelChipListInput(values: $working.dislikedFoods, placeholder: String(localized: "Mushrooms, olives…"), id: "fuelWontEat")
                sectionLabel(String(localized: "Sick of these"))
                FuelChipListInput(values: $working.boredOfFoods, placeholder: String(localized: "Chicken, oats…"), id: "fuelBored")
            }
        case .favourites:
            VStack(alignment: .leading, spacing: Tide.s4) {
                sectionLabel(String(localized: "Foods"))
                FuelChipListInput(values: $working.favoriteFoods, placeholder: String(localized: "Salmon, rice, eggs…"), id: "fuelFavourites")
                sectionLabel(String(localized: "Cuisines"))
                FuelChipListInput(
                    values: $working.favoriteCuisines, placeholder: String(localized: "Italian, Mexican…"),
                    suggestions: Self.cuisineSuggestions, id: "fuelCuisines"
                )
            }
        case .tastes:
            VStack(alignment: .leading, spacing: Tide.s4) {
                FuelPillPicker(
                    label: String(localized: "How spicy?"),
                    options: SpiceLevel.allCases.map { ($0, $0.displayName) },
                    selection: $working.spiceLevel, id: "fuelSpice"
                )
                FuelPillPicker(
                    label: String(localized: "Breakfast style"),
                    options: BreakfastStyle.allCases.map { ($0, $0.displayName) },
                    selection: $working.breakfastStyle, id: "fuelBreakfastStyle"
                )
            }
        case .appetite:
            VStack(alignment: .leading, spacing: Tide.s4) {
                FuelPillPicker(
                    label: String(localized: "Snacks a day"),
                    options: SnackHabit.range.map { ($0, $0 == 0 ? String(localized: "None") : "\($0)") },
                    selection: $working.snacksPerDay, id: "fuelSnacks"
                )
                FuelPillPicker(
                    label: String(localized: "Portion size"),
                    options: AppetiteSize.allCases.map { ($0, $0.displayName) },
                    selection: $working.appetite, id: "fuelAppetite"
                )
            }
        case .skill:
            choiceStack {
                ForEach(CookingSkill.allCases, id: \.self) { skill in
                    FuelChoiceCard(title: skill.displayName, subtitle: Self.skillBlurb(skill), isSelected: working.cookingSkill == skill) {
                        working.cookingSkill = skill
                    }
                }
            }
        case .cookTimes: cookTimes
        case .leftovers:
            choiceStack {
                ForEach(LeftoverTolerance.allCases) { tolerance in
                    FuelChoiceCard(title: tolerance.displayName, isSelected: working.leftoverTolerance == tolerance) {
                        working.leftoverTolerance = tolerance
                    }
                }
            }
        case .equipment: equipment
        case .clearSkin:
            choiceStack {
                FuelChoiceCard(title: String(localized: "On"), subtitle: String(localized: "Plan around clearer skin"), icon: "sparkles", isSelected: working.clearSkinFocus) {
                    working.clearSkinFocus = true
                }
                FuelChoiceCard(title: String(localized: "Off"), subtitle: String(localized: "Normal planning"), icon: "circle.slash", isSelected: !working.clearSkinFocus) {
                    working.clearSkinFocus = false
                }
            }
        case .shopping:
            VStack(alignment: .leading, spacing: Tide.s4) {
                FuelNumberField(
                    value: intBinding(\.weeklyBudgetUSD),
                    unit: String(localized: "$ / week"),
                    label: String(localized: "Budget"),
                    keyboard: .numberPad,
                    id: "fuelBudget"
                )
                sectionLabel(String(localized: "Where you shop"))
                FuelChipListInput(
                    values: $working.stores, placeholder: String(localized: "Walmart, Aldi…"),
                    suggestions: ["Walmart", "Costco", "Trader Joe's", "Aldi", "Publix", "Whole Foods"], id: "fuelStores"
                )
            }
        case .recovery:
            choiceStack {
                FuelChoiceCard(
                    title: String(localized: "Follow my recovery"),
                    subtitle: String(localized: "Heavier fuel after hard days, lighter on rest"),
                    icon: "heart.fill",
                    isSelected: working.recoveryAdjusted
                ) {
                    working.recoveryAdjusted = true
                }
                FuelChoiceCard(
                    title: String(localized: "Same every day"),
                    subtitle: String(localized: "Ignore recovery data"),
                    icon: "equal",
                    isSelected: !working.recoveryAdjusted
                ) {
                    working.recoveryAdjusted = false
                }
            }
        }
    }

    static let cuisineSuggestions = ["Italian", "Mexican", "Asian", "Mediterranean", "Indian", "American"]

    private func sectionLabel(_ text: String) -> some View {
        TideSectionLabel(title: text)
    }

    /// A stack of choice tiles: one glass group, so the tiles sample the field together.
    private func choiceStack(@ViewBuilder _ content: () -> some View) -> some View {
        GlassEffectContainer(spacing: Tide.s1) {
            VStack(spacing: Tide.s2) {
                content()
            }
        }
    }

    /// Weight, height and age together, only the ones Health doesn't supply.
    private var bodyStats: some View {
        VStack(spacing: Tide.s2) {
            if !locked.contains(.weight) {
                FuelNumberField(value: weightBinding(\.weightKg), unit: unit.abbreviation, label: String(localized: "Weight"), id: "fuelWeight")
            }
            if !locked.contains(.height) {
                FuelNumberField(value: $working.heightCm, unit: String(localized: "cm"), label: String(localized: "Height"), id: "fuelHeight")
            }
            if !locked.contains(.age) {
                FuelNumberField(value: intBinding(\.age), unit: String(localized: "yrs"), label: String(localized: "Age"), keyboard: .numberPad, id: "fuelAge")
            }
        }
    }

    private static func skillBlurb(_ skill: CookingSkill) -> String {
        switch skill {
        case .beginner: String(localized: "Few ingredients, one pan")
        case .intermediate: String(localized: "Comfortable with most recipes")
        case .advanced: String(localized: "Anything goes")
        }
    }

    // MARK: - Step bodies

    private var healthBody: some View {
        VStack(spacing: 0) {
            HStack {
                HealthBadge()
                Spacer()
            }
            .padding(.bottom, Tide.s2)
            if locked.contains(.weight), let kg = working.weightKg {
                FuelHealthRow(label: String(localized: "Weight"), value: "\(Int(WeightUnit.kg.convert(kg, to: unit).rounded())) \(unit.abbreviation)")
                Divider().overlay(Tide.hairline)
            }
            if locked.contains(.height), let cm = working.heightCm {
                FuelHealthRow(label: String(localized: "Height"), value: String(localized: "\(Int(cm.rounded())) cm"))
                Divider().overlay(Tide.hairline)
            }
            if locked.contains(.age), let age = working.age {
                FuelHealthRow(label: String(localized: "Age"), value: String(localized: "\(age) yrs"))
                Divider().overlay(Tide.hairline)
            }
            if locked.contains(.sex), let sex = working.sex {
                FuelHealthRow(label: String(localized: "Sex"), value: sex.displayName)
                Divider().overlay(Tide.hairline)
            }
            if locked.contains(.bodyFat), let fat = working.bodyFatPercent {
                FuelHealthRow(label: String(localized: "Body fat"), value: "\(fat.tempoDecimal(1)) %")
            }
            let missing = FuelBodyField.allCases.filter { !locked.contains($0) && $0 != .bodyFat }
            if !missing.isEmpty {
                Text("Next: the few things Health doesn't have.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Tide.s3)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private var goalChoices: some View {
        choiceStack {
            ForEach(DietaryGoal.allCases, id: \.self) { goal in
                FuelChoiceCard(
                    title: goal.displayName,
                    subtitle: Self.goalBlurb(goal),
                    icon: Self.goalIcon(goal),
                    isSelected: working.goal == goal
                ) {
                    working.goal = goal
                }
            }
        }
    }

    private static func goalBlurb(_ goal: DietaryGoal) -> String {
        switch goal {
        case .leanGain: String(localized: "Build muscle on a small surplus")
        case .cut: String(localized: "Lose fat, keep the muscle")
        case .maintain: String(localized: "Hold your weight, eat well")
        }
    }

    private static func goalIcon(_ goal: DietaryGoal) -> String {
        switch goal {
        case .leanGain: "arrow.up.right"
        case .cut: "arrow.down.right"
        case .maintain: "equal"
        }
    }

    private var goalTarget: some View {
        VStack(spacing: Tide.s2) {
            FuelNumberField(value: weightBinding(\.goalWeightKg), unit: unit.abbreviation, label: String(localized: "Goal weight"), id: "fuelGoalWeight")
            FuelNumberField(value: weightBinding(\.weeklyRateKg), unit: String(localized: "\(unit.abbreviation) / wk"), label: String(localized: "Per week"), id: "fuelRate")
        }
    }

    private var windowPicker: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            let hasWindow = working.eatingWindowStartMinutes != nil
            choiceStack {
                FuelChoiceCard(
                    title: String(localized: "Set a window"),
                    subtitle: String(localized: "Meals stay between your first and last"),
                    icon: "clock.fill",
                    isSelected: hasWindow
                ) {
                    working.eatingWindowStartMinutes = working.eatingWindowStartMinutes ?? 8 * 60
                    working.eatingWindowEndMinutes = working.eatingWindowEndMinutes ?? 21 * 60
                }
                FuelChoiceCard(title: String(localized: "No fixed window"), subtitle: String(localized: "Spread meals around my day"), icon: "infinity", isSelected: !hasWindow) {
                    working.eatingWindowStartMinutes = nil
                    working.eatingWindowEndMinutes = nil
                }
            }
            if hasWindow {
                timeRow(String(localized: "First meal"), minutes: $working.eatingWindowStartMinutes, fallback: 8 * 60)
                timeRow(String(localized: "Last meal"), minutes: $working.eatingWindowEndMinutes, fallback: 21 * 60)
                if !FuelFlowStep.window.isValid(in: working) {
                    Text("Last meal has to come after the first.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                } else if let spacing = working.mealSpacingText, let meals = working.mealsPerDay {
                    Text("\(FuelWords.count(meals, "meal")) · \(spacing.lowercased())")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
        }
    }

    private func timeRow(_ label: String, minutes: Binding<Int?>, fallback: Int) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .tideLabel()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Tide.s3)
            DatePicker("", selection: Binding(
                get: { OptionalTimeRow.date(minutes.wrappedValue ?? fallback) },
                set: { minutes.wrappedValue = OptionalTimeRow.minutes($0) }
            ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: Tide.fuelWheel)
                .clipped()
        }
        .padding(.horizontal, Tide.s3)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
    }

    /// The seven days as one glass card of rows, not seven cards.
    private var weekDays: some View {
        FuelRowGroup {
            ForEach(working.routine.days) { day in
                NavigationLink {
                    DayRoutineEditor(day: $working.routine[day.weekday], places: working.routine.places)
                } label: {
                    HStack(spacing: Tide.s3) {
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            Text(day.name)
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                            Text(Self.daySummary(of: day, places: working.routine.places))
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuelDay\(day.weekday)")
            }
        }
    }

    static func daySummary(of day: DayRoutine, places: [RoutinePlace]) -> String {
        var parts: [String] = []
        if let wake = RoutineTime.string(day.wakeMinutes) {
            parts.append(String(localized: "Up \(wake)"))
        }
        if let leave = RoutineTime.string(day.leaveHomeMinutes) {
            parts.append(String(localized: "out \(leave)"))
        }
        if let back = RoutineTime.string(day.backHomeMinutes) {
            parts.append(String(localized: "home \(back)"))
        }
        if let training = day.training, let time = RoutineTime.string(training.startMinutes) {
            parts.append(String(localized: "train \(time)"))
        }
        for event in day.events where event.kind == .mealOut {
            let place = event.restaurants.first ?? places.first { $0.id == event.placeID }?.name ?? String(localized: "out", comment: "Place name fallback in a day summary, as in: eat out 13:00")
            let eatTime = RoutineTime.string(event.startMinutes) ?? ""
            parts.append(String(localized: "eat \(place) \(eatTime)"))
        }
        let classes = day.events.filter { $0.kind == .classOrWork }.count
        if classes > 0 {
            parts.append(String(localized: "\(classes) class/work"))
        }
        return parts.isEmpty ? String(localized: "Not set. Tap to add.") : parts.joined(separator: " · ")
    }

    private var places: some View {
        VStack(spacing: Tide.s2) {
            ForEach($working.routine.places) { $place in
                VStack(alignment: .leading, spacing: Tide.s2) {
                    HStack(spacing: Tide.s2) {
                        TextField("Place", text: $place.name)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                        if place.hasCoordinate {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Tide.good)
                                .accessibilityLabel("Found on the map")
                        }
                        Button {
                            working.routine.places.removeAll { $0.id == place.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text2)
                                .frame(width: Tide.hit, height: Tide.hit)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove place")
                    }
                    TextField("Restaurants you eat at here", text: Binding(
                        get: { place.usualRestaurants.joined(separator: ", ") },
                        set: { place.usualRestaurants = FuelSetupText.split($0) }
                    ))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                }
                .padding(.leading, Tide.s4)
                .padding(.trailing, Tide.s1)
                .padding(.vertical, Tide.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
            }
            Button {
                working.routine.places.append(RoutinePlace(name: ""))
            } label: {
                Label("Add a place", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
        }
    }

    private var restrictions: some View {
        FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
            ForEach(DietRestriction.allCases) { restriction in
                let on = working.restrictions.contains(restriction)
                Button {
                    HapticManager.selection()
                    if on {
                        working.restrictions.remove(restriction)
                    } else {
                        working.restrictions.insert(restriction)
                    }
                } label: {
                    HStack(spacing: Tide.s1) {
                        if on {
                            Image(systemName: "checkmark")
                                .font(Tide.label)
                        }
                        Text(restriction.label)
                    }
                    .font(Tide.bodyStrong)
                    .foregroundStyle(on ? Tide.ink : Tide.text)
                    .padding(.horizontal, Tide.s4)
                    .frame(minHeight: Tide.hit)
                    .background(on ? mood.accent : Tide.fill, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .animation(Tide.snap, value: on)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var cookTimes: some View {
        VStack(spacing: Tide.s2) {
            FuelBigStepper(
                value: $working.cookableDaysPerWeek,
                defaultValue: 4,
                range: 0 ... 7,
                unit: String(localized: "days"),
                label: String(localized: "Days you cook"),
                id: "fuelCookDays"
            )
            FuelBigStepper(
                value: $working.cookMinutesWeekday,
                defaultValue: 30,
                range: 0 ... 180,
                step: 5,
                unit: String(localized: "min"),
                label: String(localized: "Weekdays"),
                id: "fuelCookWeekday"
            )
            FuelBigStepper(
                value: $working.cookMinutesWeekend,
                defaultValue: 60,
                range: 0 ... 240,
                step: 5,
                unit: String(localized: "min"),
                label: String(localized: "Weekends"),
                id: "fuelCookWeekend"
            )
        }
    }

    private var equipment: some View {
        GlassEffectContainer(spacing: Tide.s1) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Tide.s2), GridItem(.flexible(), spacing: Tide.s2)], spacing: Tide.s2) {
                ForEach(KitchenApplianceKind.allCases, id: \.self) { kind in
                    let owned = working.equipment[kind.rawValue] ?? kind.seededAvailable
                    Button {
                        HapticManager.selection()
                        working.equipment[kind.rawValue] = !owned
                    } label: {
                        VStack(spacing: Tide.s2) {
                            Image(systemName: kind.icon)
                                .font(Tide.title2)
                                .foregroundStyle(owned ? mood.accent : Tide.text3)
                                .frame(minHeight: Tide.icon + Tide.s1)
                                .accessibilityHidden(true)
                            Text(kind.displayName)
                                .font(Tide.body)
                                .foregroundStyle(owned ? Tide.text : Tide.text2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minHeight: Tide.s10 + Tide.s6)
                        .tideCard(padding: Tide.s2, radius: Tide.tileRadius)
                        .overlay {
                            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                                .strokeBorder(mood.accent, lineWidth: 1.5)
                                .opacity(owned ? 1 : 0)
                        }
                        .contentShape(.rect(cornerRadius: Tide.tileRadius))
                    }
                    .buttonStyle(FuelPressStyle())
                    .animation(Tide.snap, value: owned)
                    .accessibilityAddTraits(owned ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Bindings

    private func weightBinding(_ keyPath: WritableKeyPath<FuelSetupDraft, Double?>) -> Binding<Double?> {
        Binding(
            get: { working[keyPath: keyPath].map { WeightUnit.kg.convert($0, to: unit) } },
            set: { working[keyPath: keyPath] = $0.map { unit.convert($0, to: .kg) } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<FuelSetupDraft, Int?>) -> Binding<Double?> {
        Binding(
            get: { working[keyPath: keyPath].map(Double.init) },
            set: { working[keyPath: keyPath] = $0.map { Int($0.rounded()) } }
        )
    }
}
