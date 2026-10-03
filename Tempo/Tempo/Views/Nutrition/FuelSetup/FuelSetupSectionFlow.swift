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
    @State
    private var isSaving = false

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
            return "Save & next: \(chainNext.title)"
        }
        return isChain ? "Save & finish" : "Save"
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
            onBack: { withAnimation(TempoAnimation.springMedium) { index = max(0, index - 1) } },
            onNext: next,
            onClose: onClose
        ) {
            stepContent
        }
        .id(step)
        .transition(.opacity)
    }

    private func next() {
        KeyboardDismisser.dismiss()
        if index < steps.count - 1 {
            withAnimation(TempoAnimation.springMedium) { index += 1 }
            return
        }
        save()
    }

    /// Leaves this question as it is (optional questions only).
    private func skip() {
        KeyboardDismisser.dismiss()
        if index < steps.count - 1 {
            withAnimation(TempoAnimation.springMedium) { index += 1 }
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
        case .healthBody: "Your body"
        case .bodyStats: "About you"
        case .sex: "Male or female?"
        case .bodyFat: "Body fat?"
        case .goal: "What's the goal?"
        case .goalTarget: "Where to?"
        case .trainingDays: "Training days a week"
        case .meals: "Meals a day"
        case .window: "Eating window"
        case .weekDays: "Your week"
        case .places: "Where you eat"
        case .notes: "Anything else?"
        case .restrictions: "Diet rules and allergies"
        case .wontEat: "Never serve me"
        case .favourites: "Foods you love"
        case .tastes: "Your taste"
        case .appetite: "Snacks and portions"
        case .skill: "How good are you in the kitchen?"
        case .cookTimes: "Cooking time"
        case .leftovers: "Leftovers"
        case .equipment: "What's in your kitchen?"
        case .clearSkin: "Clear-skin focus"
        case .shopping: "Budget and stores"
        case .recovery: "Recovery-adjusted meals"
        }
    }

    static func subtitle(for step: FuelFlowStep) -> String? {
        switch step {
        case .healthBody: "Straight from Apple Health. Change it there, not here."
        case .bodyStats: "For your calorie and protein targets."
        case .sex: "Biological sex, for the calorie formula."
        case .bodyFat: "Optional. Skip it if you don't know."
        case .goal: "Pick one. The plan is built around it."
        case .goalTarget: "Your target weight and how fast."
        case .trainingDays: "Fuel follows the days you train."
        case .meals: "Including the snacks you plan."
        case .window: "First and last meal. The plan fits inside it."
        case .weekDays: "Tap a day: wake-up, classes or work, training."
        case .places: "Campus, work, gym. We look up restaurants nearby."
        case .notes: "Anything the planner should know."
        case .restrictions: "Tap all that apply. None is fine. Allergies are never in your plan."
        case .wontEat: "Never-foods are permanent. Sick-of foods rotate down for a while."
        case .favourites: "These show up more often."
        case .tastes: "Tap again to clear. No pick means no preference."
        case .appetite: "The daily macros stay the same. This shapes the meals."
        case .skill: "Sets how complex the recipes get."
        case .cookTimes: "Days you cook, and minutes for one meal. The rest of the week is quick or leftovers."
        case .leftovers: "How you feel about eating the same meal again."
        case .equipment: "The planner only programs recipes you can make."
        case .clearSkin: "Low-GI carbs, no added sweeteners, minimal dairy. Macros stay the same."
        case .shopping: "The grocery list stays under your budget."
        case .recovery: "More carbs on training days, lighter on rest days, using your recovery data."
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .healthBody: healthBody
        case .bodyStats: bodyStats
        case .sex:
            VStack(spacing: TempoSpacing.sm) {
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    FuelChoiceCard(title: sex.displayName, icon: sex == .male ? "figure.stand" : "figure.stand.dress", isSelected: working.sex == sex) {
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
                unit: "days",
                id: "fuelTrainingDays"
            )
        case .meals:
            VStack(spacing: TempoSpacing.sm) {
                FuelBigStepper(value: $working.mealsPerDay, defaultValue: 4, range: 1 ... 8, unit: "meals", label: "Meals a day", id: "fuelMeals")
                FuelChoiceCard(title: "I eat breakfast", subtitle: "First meal in the morning", icon: "sunrise.fill", isSelected: working.breakfastSkipped == false) {
                    working.breakfastSkipped = false
                }
                FuelChoiceCard(title: "I skip it", subtitle: "First meal comes later", icon: "moon.zzz.fill", isSelected: working.breakfastSkipped == true) {
                    working.breakfastSkipped = true
                }
            }
        case .window: windowPicker
        case .weekDays: weekDays
        case .places: places
        case .notes:
            TextField("Notes for your planner", text: $working.notes, axis: .vertical)
                .font(.tempoBody)
                .lineLimit(4 ... 10)
                .padding(TempoSpacing.md)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        case .restrictions:
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                restrictions
                sectionLabel("ALLERGIES")
                FuelChipListInput(
                    values: $working.allergies, placeholder: "Peanuts, shellfish…",
                    suggestions: ["Peanuts", "Tree nuts", "Shellfish", "Eggs", "Soy"], id: "fuelAllergies"
                )
            }
        case .wontEat:
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                sectionLabel("NEVER SERVE ME")
                FuelChipListInput(values: $working.dislikedFoods, placeholder: "Mushrooms, olives…", id: "fuelWontEat")
                sectionLabel("SICK OF THESE")
                FuelChipListInput(values: $working.boredOfFoods, placeholder: "Chicken, oats…", id: "fuelBored")
            }
        case .favourites:
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                sectionLabel("FOODS")
                FuelChipListInput(values: $working.favoriteFoods, placeholder: "Salmon, rice, eggs…", id: "fuelFavourites")
                sectionLabel("CUISINES")
                FuelChipListInput(
                    values: $working.favoriteCuisines, placeholder: "Italian, Mexican…",
                    suggestions: Self.cuisineSuggestions, id: "fuelCuisines"
                )
            }
        case .tastes:
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                FuelPillPicker(
                    label: "How spicy?",
                    options: SpiceLevel.allCases.map { ($0, $0.displayName) },
                    selection: $working.spiceLevel, id: "fuelSpice"
                )
                FuelPillPicker(
                    label: "Breakfast style",
                    options: BreakfastStyle.allCases.map { ($0, $0.displayName) },
                    selection: $working.breakfastStyle, id: "fuelBreakfastStyle"
                )
            }
        case .appetite:
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                FuelPillPicker(
                    label: "Snacks a day",
                    options: SnackHabit.range.map { ($0, $0 == 0 ? "None" : "\($0)") },
                    selection: $working.snacksPerDay, id: "fuelSnacks"
                )
                FuelPillPicker(
                    label: "Portion size",
                    options: AppetiteSize.allCases.map { ($0, $0.displayName) },
                    selection: $working.appetite, id: "fuelAppetite"
                )
            }
        case .skill:
            VStack(spacing: TempoSpacing.sm) {
                ForEach(CookingSkill.allCases, id: \.self) { skill in
                    FuelChoiceCard(title: skill.displayName, subtitle: Self.skillBlurb(skill), isSelected: working.cookingSkill == skill) {
                        working.cookingSkill = skill
                    }
                }
            }
        case .cookTimes: cookTimes
        case .leftovers:
            VStack(spacing: TempoSpacing.sm) {
                ForEach(LeftoverTolerance.allCases) { tolerance in
                    FuelChoiceCard(title: tolerance.displayName, isSelected: working.leftoverTolerance == tolerance) {
                        working.leftoverTolerance = tolerance
                    }
                }
            }
        case .equipment: equipment
        case .clearSkin:
            VStack(spacing: TempoSpacing.sm) {
                FuelChoiceCard(title: "On", subtitle: "Plan around clearer skin", icon: "sparkles", isSelected: working.clearSkinFocus) {
                    working.clearSkinFocus = true
                }
                FuelChoiceCard(title: "Off", subtitle: "Normal planning", icon: "circle.slash", isSelected: !working.clearSkinFocus) {
                    working.clearSkinFocus = false
                }
            }
        case .shopping:
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                FuelNumberField(value: intBinding(\.weeklyBudgetUSD), unit: "$ / week", label: "Budget", keyboard: .numberPad, id: "fuelBudget")
                sectionLabel("WHERE YOU SHOP")
                FuelChipListInput(
                    values: $working.stores, placeholder: "Walmart, Aldi…",
                    suggestions: ["Walmart", "Costco", "Trader Joe's", "Aldi", "Publix", "Whole Foods"], id: "fuelStores"
                )
            }
        case .recovery:
            VStack(spacing: TempoSpacing.sm) {
                FuelChoiceCard(title: "Follow my recovery", subtitle: "Heavier fuel after hard days, lighter on rest", icon: "heart.fill", isSelected: working.recoveryAdjusted) {
                    working.recoveryAdjusted = true
                }
                FuelChoiceCard(title: "Same every day", subtitle: "Ignore recovery data", icon: "equal", isSelected: !working.recoveryAdjusted) {
                    working.recoveryAdjusted = false
                }
            }
        }
    }

    static let cuisineSuggestions = ["Italian", "Mexican", "Asian", "Mediterranean", "Indian", "American"]

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.tempoModuleTag)
            .tracking(TempoTracking.drillLabel)
            .foregroundStyle(Color.tempoTextTertiary)
    }

    /// Weight, height and age together, only the ones Health doesn't supply.
    private var bodyStats: some View {
        VStack(spacing: TempoSpacing.sm) {
            if !locked.contains(.weight) {
                FuelNumberField(value: weightBinding(\.weightKg), unit: unit.abbreviation, label: "Weight", id: "fuelWeight")
            }
            if !locked.contains(.height) {
                FuelNumberField(value: $working.heightCm, unit: "cm", label: "Height", id: "fuelHeight")
            }
            if !locked.contains(.age) {
                FuelNumberField(value: intBinding(\.age), unit: "yrs", label: "Age", keyboard: .numberPad, id: "fuelAge")
            }
        }
    }

    private static func skillBlurb(_ skill: CookingSkill) -> String {
        switch skill {
        case .beginner: "Few ingredients, one pan"
        case .intermediate: "Comfortable with most recipes"
        case .advanced: "Anything goes"
        }
    }

    // MARK: - Step bodies

    private var healthBody: some View {
        VStack(spacing: 0) {
            HStack {
                HealthBadge()
                Spacer()
            }
            .padding(.bottom, TempoSpacing.sm)
            if locked.contains(.weight), let kg = working.weightKg {
                FuelHealthRow(label: "Weight", value: "\(Int(WeightUnit.kg.convert(kg, to: unit).rounded())) \(unit.abbreviation)")
                Divider().overlay(Color.tempoDivider)
            }
            if locked.contains(.height), let cm = working.heightCm {
                FuelHealthRow(label: "Height", value: "\(Int(cm.rounded())) cm")
                Divider().overlay(Color.tempoDivider)
            }
            if locked.contains(.age), let age = working.age {
                FuelHealthRow(label: "Age", value: "\(age) yrs")
                Divider().overlay(Color.tempoDivider)
            }
            if locked.contains(.sex), let sex = working.sex {
                FuelHealthRow(label: "Sex", value: sex.displayName)
                Divider().overlay(Color.tempoDivider)
            }
            if locked.contains(.bodyFat), let fat = working.bodyFatPercent {
                FuelHealthRow(label: "Body fat", value: "\(String(format: "%.1f", fat)) %")
            }
            let missing = FuelBodyField.allCases.filter { !locked.contains($0) && $0 != .bodyFat }
            if !missing.isEmpty {
                Text("Next: the few things Health doesn't have.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, TempoSpacing.md)
            }
        }
        .padding(TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private var goalChoices: some View {
        VStack(spacing: TempoSpacing.sm) {
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
        case .leanGain: "Build muscle on a small surplus"
        case .cut: "Lose fat, keep the muscle"
        case .maintain: "Hold your weight, eat well"
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
        VStack(spacing: TempoSpacing.sm) {
            FuelNumberField(value: weightBinding(\.goalWeightKg), unit: unit.abbreviation, label: "Goal weight", id: "fuelGoalWeight")
            FuelNumberField(value: weightBinding(\.weeklyRateKg), unit: "\(unit.abbreviation) / wk", label: "Per week", id: "fuelRate")
        }
    }

    private var windowPicker: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            let hasWindow = working.eatingWindowStartMinutes != nil
            FuelChoiceCard(title: "Set a window", subtitle: "Meals stay between your first and last", icon: "clock.fill", isSelected: hasWindow) {
                working.eatingWindowStartMinutes = working.eatingWindowStartMinutes ?? 8 * 60
                working.eatingWindowEndMinutes = working.eatingWindowEndMinutes ?? 21 * 60
            }
            FuelChoiceCard(title: "No fixed window", subtitle: "Spread meals around my day", icon: "infinity", isSelected: !hasWindow) {
                working.eatingWindowStartMinutes = nil
                working.eatingWindowEndMinutes = nil
            }
            if hasWindow {
                timeRow("FIRST MEAL", minutes: $working.eatingWindowStartMinutes, fallback: 8 * 60)
                timeRow("LAST MEAL", minutes: $working.eatingWindowEndMinutes, fallback: 21 * 60)
                if !FuelFlowStep.window.isValid(in: working) {
                    Text("Last meal has to come after the first.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                } else if let spacing = working.mealSpacingText, let meals = working.mealsPerDay {
                    Text("\(meals) meals · \(spacing.lowercased())")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
    }

    private func timeRow(_ label: String, minutes: Binding<Int?>, fallback: Int) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, TempoSpacing.md)
            DatePicker("", selection: Binding(
                get: { OptionalTimeRow.date(minutes.wrappedValue ?? fallback) },
                set: { minutes.wrappedValue = OptionalTimeRow.minutes($0) }
            ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .clipped()
        }
        .padding(.horizontal, TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    private var weekDays: some View {
        VStack(spacing: TempoSpacing.sm) {
            ForEach(working.routine.days) { day in
                NavigationLink {
                    DayRoutineEditor(day: $working.routine[day.weekday], places: working.routine.places)
                } label: {
                    HStack(spacing: TempoSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.name)
                                .font(.tempoBodyBold)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Text(Self.daySummary(of: day, places: working.routine.places))
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .padding(TempoSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuelDay\(day.weekday)")
            }
        }
    }

    static func daySummary(of day: DayRoutine, places: [RoutinePlace]) -> String {
        var parts: [String] = []
        if let wake = RoutineTime.string(day.wakeMinutes) {
            parts.append("Up \(wake)")
        }
        if let leave = RoutineTime.string(day.leaveHomeMinutes) {
            parts.append("out \(leave)")
        }
        if let back = RoutineTime.string(day.backHomeMinutes) {
            parts.append("home \(back)")
        }
        if let training = day.training, let time = RoutineTime.string(training.startMinutes) {
            parts.append("train \(time)")
        }
        for event in day.events where event.kind == .mealOut {
            let place = event.restaurants.first ?? places.first { $0.id == event.placeID }?.name ?? "out"
            parts.append("eat \(place) \(RoutineTime.string(event.startMinutes) ?? "")")
        }
        let classes = day.events.filter { $0.kind == .classOrWork }.count
        if classes > 0 {
            parts.append("\(classes) class/work")
        }
        return parts.isEmpty ? "Not set. Tap to add." : parts.joined(separator: " · ")
    }

    private var places: some View {
        VStack(spacing: TempoSpacing.sm) {
            ForEach($working.routine.places) { $place in
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    HStack {
                        TextField("Place", text: $place.name)
                            .font(.tempoBodyBold)
                        if place.hasCoordinate {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Color.tempoSuccess)
                                .accessibilityLabel("Found on the map")
                        }
                        Button {
                            working.routine.places.removeAll { $0.id == place.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                        .accessibilityLabel("Remove place")
                    }
                    TextField("Restaurants you eat at here", text: Binding(
                        get: { place.usualRestaurants.joined(separator: ", ") },
                        set: { place.usualRestaurants = FuelSetupText.split($0) }
                    ))
                    .font(.tempoCaption1)
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            }
            Button {
                working.routine.places.append(RoutinePlace(name: ""))
            } label: {
                Label("Add a place", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)
        }
    }

    private var restrictions: some View {
        FlowLayout(spacing: TempoSpacing.sm, lineSpacing: TempoSpacing.sm) {
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
                    HStack(spacing: TempoSpacing.xs) {
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(restriction.label)
                    }
                    .font(.tempoBodyBold)
                    .foregroundStyle(on ? Color.tempoTextInverse : Color.tempoTextPrimary)
                    .padding(.horizontal, TempoSpacing.lg)
                    .padding(.vertical, TempoSpacing.md)
                    .background(on ? Color.tempoSignal : Color.tempoSurfaceCard)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(on ? Color.clear : Color.tempoBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var cookTimes: some View {
        VStack(spacing: TempoSpacing.sm) {
            FuelBigStepper(value: $working.cookableDaysPerWeek, defaultValue: 4, range: 0 ... 7, unit: "days", label: "Days you cook", id: "fuelCookDays")
            FuelBigStepper(value: $working.cookMinutesWeekday, defaultValue: 30, range: 0 ... 180, step: 5, unit: "min", label: "Weekdays", id: "fuelCookWeekday")
            FuelBigStepper(value: $working.cookMinutesWeekend, defaultValue: 60, range: 0 ... 240, step: 5, unit: "min", label: "Weekends", id: "fuelCookWeekend")
        }
    }

    private var equipment: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: TempoSpacing.sm), GridItem(.flexible(), spacing: TempoSpacing.sm)], spacing: TempoSpacing.sm) {
            ForEach(KitchenApplianceKind.allCases, id: \.self) { kind in
                let owned = working.equipment[kind.rawValue] ?? kind.seededAvailable
                Button {
                    HapticManager.selection()
                    working.equipment[kind.rawValue] = !owned
                } label: {
                    VStack(spacing: TempoSpacing.sm) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(owned ? Color.tempoSignal : Color.tempoTextTertiary)
                            .frame(height: 30)
                        Text(kind.displayName)
                            .font(.tempoCallout)
                            .foregroundStyle(owned ? Color.tempoTextPrimary : Color.tempoTextTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                            .stroke(owned ? Color.tempoSignal : Color.tempoBorder, lineWidth: owned ? 2 : 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(owned ? .isSelected : [])
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
