//
// FuelSetupSectionFlow.swift
// Tempo
//
// One section of the Fuel setup as an onboarding-style flow: one question per
// screen, big tappable answers, progress dots, Back / Next, and a Save on the
// last screen that writes ONLY this section. Edits happen on a working copy,
// so closing the flow throws them away.
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
        onSave: @escaping (FuelSetupDraft) async -> Void,
        onClose: @escaping () -> Void
    ) {
        self.section = section
        self.locked = locked
        self.unit = unit
        self.onSave = onSave
        self.onClose = onClose
        _working = State(initialValue: draft)
    }

    private var steps: [FuelFlowStep] {
        let steps = FuelFlowStep.steps(for: section, draft: working, locked: locked)
        return steps.isEmpty ? [.healthBody] : steps
    }

    private var step: FuelFlowStep {
        steps[min(index, steps.count - 1)]
    }

    var body: some View {
        FuelFlowScaffold(
            title: Self.title(for: step),
            subtitle: Self.subtitle(for: step),
            index: min(index, steps.count - 1),
            count: steps.count,
            canContinue: step.isValid(in: working),
            isSaving: isSaving,
            isLast: index >= steps.count - 1,
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
        case .weight: "How much do you weigh?"
        case .height: "How tall are you?"
        case .age: "How old are you?"
        case .sex: "Male or female?"
        case .bodyFat: "Body fat?"
        case .goal: "What's the goal?"
        case .goalTarget: "Where to?"
        case .trainingDays: "Training days a week"
        case .mealsCount: "Meals a day"
        case .breakfast: "Breakfast?"
        case .window: "Eating window"
        case .weekDays: "Your week"
        case .places: "Where you eat"
        case .notes: "Anything else?"
        case .restrictions: "Diet rules"
        case .allergies: "Allergies"
        case .wontEat: "Never serve me"
        case .favourites: "Foods you love"
        case .bored: "Sick of these"
        case .skill: "How good are you in the kitchen?"
        case .cookDays: "Days you can cook"
        case .cookTimes: "Time to cook"
        case .leftovers: "Leftovers"
        case .equipment: "What's in your kitchen?"
        case .clearSkin: "Clear-skin focus"
        case .budget: "Weekly food budget"
        case .stores: "Where you shop"
        case .recovery: "Recovery-adjusted meals"
        }
    }

    static func subtitle(for step: FuelFlowStep) -> String? {
        switch step {
        case .healthBody: "Straight from Apple Health. Change it there, not here."
        case .weight: "Used for your calorie and protein targets."
        case .height: "In centimetres."
        case .age: "For the calorie formula."
        case .sex: "Biological sex, for the calorie formula."
        case .bodyFat: "Optional. Skip it if you don't know."
        case .goal: "Pick one. The plan is built around it."
        case .goalTarget: "Your target weight and how fast."
        case .trainingDays: "Fuel follows the days you train."
        case .mealsCount: "Including snacks you plan."
        case .breakfast: "No judgement. The plan adapts."
        case .window: "First and last meal. The plan fits inside it."
        case .weekDays: "Tap a day: wake-up, classes or work, training. At least one wake-up time."
        case .places: "Campus, work, gym. We look up restaurants nearby."
        case .notes: "Anything the planner should know."
        case .restrictions: "Tap all that apply. None is fine."
        case .allergies: "These are never in your plan."
        case .wontEat: "Permanent. The plan never uses them."
        case .favourites: "These show up more often."
        case .bored: "These rotate down for a while."
        case .skill: "Sets how complex the recipes get."
        case .cookDays: "The rest of the week is quick or leftovers."
        case .cookTimes: "Minutes you'll spend cooking one meal."
        case .leftovers: "How you feel about eating the same meal again."
        case .equipment: "The planner only programs recipes you can make."
        case .clearSkin: "Low-GI carbs, no added sweeteners, minimal dairy. Macros stay the same."
        case .budget: "Dollars. The grocery list stays under it."
        case .stores: "Where you actually buy food."
        case .recovery: "More carbs on training days, lighter on rest days, using your recovery data."
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .healthBody: healthBody
        case .weight:
            FuelNumberField(value: weightBinding(\.weightKg), unit: unit.abbreviation, id: "fuelWeight")
        case .height:
            FuelNumberField(value: $working.heightCm, unit: "cm", id: "fuelHeight")
        case .age:
            FuelNumberField(value: intBinding(\.age), unit: "yrs", keyboard: .numberPad, id: "fuelAge")
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
        case .mealsCount:
            FuelBigStepper(value: $working.mealsPerDay, defaultValue: 4, range: 1 ... 8, unit: "meals", id: "fuelMeals")
        case .breakfast:
            VStack(spacing: TempoSpacing.sm) {
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
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        case .restrictions: restrictions
        case .allergies:
            FuelChipListInput(
                values: $working.allergies, placeholder: "Peanuts, shellfish…",
                suggestions: ["Peanuts", "Tree nuts", "Shellfish", "Eggs", "Soy"], id: "fuelAllergies"
            )
        case .wontEat:
            FuelChipListInput(values: $working.dislikedFoods, placeholder: "Mushrooms, olives…", id: "fuelWontEat")
        case .favourites:
            FuelChipListInput(values: $working.favoriteFoods, placeholder: "Salmon, rice, eggs…", id: "fuelFavourites")
        case .bored:
            FuelChipListInput(values: $working.boredOfFoods, placeholder: "Chicken, oats…", id: "fuelBored")
        case .skill:
            VStack(spacing: TempoSpacing.sm) {
                ForEach(CookingSkill.allCases, id: \.self) { skill in
                    FuelChoiceCard(title: skill.displayName, subtitle: Self.skillBlurb(skill), isSelected: working.cookingSkill == skill) {
                        working.cookingSkill = skill
                    }
                }
            }
        case .cookDays:
            FuelBigStepper(value: $working.cookableDaysPerWeek, defaultValue: 4, range: 0 ... 7, unit: "days", id: "fuelCookDays")
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
        case .budget:
            FuelNumberField(value: intBinding(\.weeklyBudgetUSD), unit: "$ / week", keyboard: .numberPad, id: "fuelBudget")
        case .stores:
            FuelChipListInput(
                values: $working.stores, placeholder: "Walmart, Aldi…",
                suggestions: ["Walmart", "Costco", "Trader Joe's", "Aldi", "Publix", "Whole Foods"], id: "fuelStores"
            )
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
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("GOAL WEIGHT")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            FuelNumberField(value: weightBinding(\.goalWeightKg), unit: unit.abbreviation, id: "fuelGoalWeight")
            Text("PER WEEK")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            FuelNumberField(value: weightBinding(\.weeklyRateKg), unit: "\(unit.abbreviation) / wk", id: "fuelRate")
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
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("WEEKDAYS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            FuelBigStepper(value: $working.cookMinutesWeekday, defaultValue: 30, range: 0 ... 180, step: 5, unit: "min", id: "fuelCookWeekday")
            Text("WEEKENDS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            FuelBigStepper(value: $working.cookMinutesWeekend, defaultValue: 60, range: 0 ... 240, step: 5, unit: "min", id: "fuelCookWeekend")
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
                            .font(.system(size: 24))
                            .foregroundStyle(owned ? Color.tempoSignal : Color.tempoTextTertiary)
                            .frame(height: 30)
                        Text(kind.displayName)
                            .font(.tempoCallout)
                            .foregroundStyle(owned ? Color.tempoTextPrimary : Color.tempoTextTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
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
