//
// FuelSetupSection.swift
// Tempo
//
// The "Edit setup" overview is a list of section cards; each one opens its
// own flow and saves ONLY its fields. This file is the pure side of that:
// which draft fields belong to which section, a one-line summary for the
// card, what is still missing, whether a section has unsaved changes, and
// which body stats are locked because Apple Health supplies them.
//

import Foundation

// MARK: - FuelSetupSection

enum FuelSetupSection: String, CaseIterable, Identifiable, Sendable {
    case you
    case goal
    case meals
    case week
    case food
    case cooking
    case shopping
    case recovery

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .you: "You"
        case .goal: "Goal"
        case .meals: "Meals & eating window"
        case .week: "Your week"
        case .food: "Food"
        case .cooking: "Cooking & kitchen"
        case .shopping: "Shopping"
        case .recovery: "Recovery"
        }
    }

    /// The planner can't work without these (body stats for the macros, the
    /// goal, and the meal pattern). Everything else is optional and has
    /// sensible defaults, so it never shows an error.
    var isRequired: Bool {
        switch self {
        case .you, .goal, .meals: true
        case .week, .food, .cooking, .shopping, .recovery: false
        }
    }

    static let required: [FuelSetupSection] = allCases.filter(\.isRequired)

    var icon: String {
        switch self {
        case .you: "person.fill"
        case .goal: "target"
        case .meals: "clock.fill"
        case .week: "calendar"
        case .food: "leaf.fill"
        case .cooking: "frying.pan.fill"
        case .shopping: "cart.fill"
        case .recovery: "heart.fill"
        }
    }
}

// MARK: - FuelBodyField

/// Body stats Apple Health can supply.
enum FuelBodyField: String, CaseIterable, Sendable {
    case weight
    case height
    case age
    case sex
    case bodyFat
}

/// What the Health app knows about the body (all optional).
struct HealthBodyStats: Equatable, Sendable {
    var weightKg: Double?
    var heightCm: Double?
    var bodyFatPercent: Double?
    var age: Int?
    var sex: BiologicalSex?

    init(weightKg: Double? = nil, heightCm: Double? = nil, bodyFatPercent: Double? = nil, age: Int? = nil, sex: BiologicalSex? = nil) {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.bodyFatPercent = bodyFatPercent
        self.age = age
        self.sex = sex
    }

    init(body: BodyCompositionData?, characteristics: HealthProfileCharacteristics) {
        self.init(
            weightKg: body?.weightKg,
            heightCm: body?.heightCm,
            bodyFatPercent: body?.bodyFatPercent,
            age: characteristics.ageYears,
            sex: characteristics.sex
        )
    }
}

// MARK: - Draft: sections

extension FuelSetupDraft {
    /// Replaces this draft's values for `section` with `other`'s — nothing else.
    mutating func copy(_ section: FuelSetupSection, from other: FuelSetupDraft) {
        switch section {
        case .you:
            weightKg = other.weightKg
            heightCm = other.heightCm
            age = other.age
            sex = other.sex
            bodyFatPercent = other.bodyFatPercent
        case .goal:
            goal = other.goal
            goalWeightKg = other.goalWeightKg
            weeklyRateKg = other.weeklyRateKg
            trainingDaysPerWeek = other.trainingDaysPerWeek
        case .meals:
            mealsPerDay = other.mealsPerDay
            breakfastSkipped = other.breakfastSkipped
            eatingWindowStartMinutes = other.eatingWindowStartMinutes
            eatingWindowEndMinutes = other.eatingWindowEndMinutes
        case .week:
            routine = other.routine
            notes = other.notes
        case .food:
            restrictions = other.restrictions
            allergies = other.allergies
            dislikedFoods = other.dislikedFoods
            favoriteFoods = other.favoriteFoods
            boredOfFoods = other.boredOfFoods
            favoriteCuisines = other.favoriteCuisines
            spiceLevel = other.spiceLevel
            breakfastStyle = other.breakfastStyle
            snacksPerDay = other.snacksPerDay
            appetite = other.appetite
        case .cooking:
            cookingSkill = other.cookingSkill
            cookMinutesWeekday = other.cookMinutesWeekday
            cookMinutesWeekend = other.cookMinutesWeekend
            cookableDaysPerWeek = other.cookableDaysPerWeek
            leftoverTolerance = other.leftoverTolerance
            equipment = other.equipment
            clearSkinFocus = other.clearSkinFocus
        case .shopping:
            weeklyBudgetUSD = other.weeklyBudgetUSD
            stores = other.stores
        case .recovery:
            recoveryAdjusted = other.recoveryAdjusted
        }
    }

    /// True when `section` differs from `saved` (the draft as last stored).
    func isDirty(_ section: FuelSetupSection, comparedTo saved: FuelSetupDraft) -> Bool {
        var probe = saved
        probe.copy(section, from: self)
        return probe != saved
    }

    /// Required answers still missing in `section` (the planner can't work without them).
    func missingFields(in section: FuelSetupSection) -> [Field] {
        let owned: Set<Field> = switch section {
        case .you: [.weight, .height, .age, .sex]
        case .goal: [.goal]
        case .meals: [.meals]
        case .week, .food, .cooking, .shopping, .recovery: []
        }
        return missingFields.filter { owned.contains($0) }
    }

    /// Required sections with an answer still missing, in overview order.
    var incompleteSections: [FuelSetupSection] {
        FuelSetupSection.allCases.filter { !missingFields(in: $0).isEmpty }
    }

    /// True when an OPTIONAL section has no answers at all (the planner uses
    /// defaults). Required sections are never "unset" — they are missing.
    func isUnset(_ section: FuelSetupSection) -> Bool {
        switch section {
        case .you, .goal, .meals: false
        case .week: routine.days.allSatisfy(\.isEmpty) && notes.isEmpty
        case .food:
            restrictions.isEmpty && allergies.isEmpty && dislikedFoods.isEmpty && favoriteFoods.isEmpty
                && boredOfFoods.isEmpty && favoriteCuisines.isEmpty && spiceLevel == nil
                && breakfastStyle == nil && snacksPerDay == nil && appetite == nil
        case .cooking:
            cookingSkill == nil && cookMinutesWeekday == nil && cookMinutesWeekend == nil
                && cookableDaysPerWeek == nil && leftoverTolerance == nil && !clearSkinFocus
        case .shopping: weeklyBudgetUSD == nil && stores.isEmpty
        case .recovery: false
        }
    }

    /// What "Finish setup" walks through, in order: the required sections
    /// still missing, then the optional ones with no answers that the user
    /// hasn't already looked at (`reviewed`: saved or skipped before).
    func remainingSections(reviewed: Set<FuelSetupSection> = []) -> [FuelSetupSection] {
        FuelSetupSection.allCases.filter { section in
            section.isRequired
                ? !missingFields(in: section).isEmpty
                : isUnset(section) && !reviewed.contains(section)
        }
    }

    /// One plain sentence naming exactly the required sections still missing
    /// ("Finish You and Goal to build your plan"), nil when nothing blocks.
    var requiredMissingMessage: String? {
        let names = incompleteSections.map(\.title)
        guard !names.isEmpty else {
            return nil
        }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return "Finish \(list) to build your plan."
    }

    /// The section after `section` in a finish chain, nil at the end.
    static func next(after section: FuelSetupSection, in chain: [FuelSetupSection]) -> FuelSetupSection? {
        guard let index = chain.firstIndex(of: section), index + 1 < chain.count else {
            return nil
        }
        return chain[index + 1]
    }

    // MARK: - Health-sourced body stats

    /// Puts what Apple Health knows into the draft and returns which body
    /// fields it supplied. Those are read-only in the editor; only what Health
    /// doesn't have is asked.
    @discardableResult
    mutating func apply(health: HealthBodyStats) -> Set<FuelBodyField> {
        apply(health: health, untouchedSince: nil)
    }

    /// Same, but a slow Health fetch must not overwrite what the user already
    /// typed: with `saved` given, a field whose draft value differs from the
    /// saved one was edited, so it is left alone (and not locked).
    @discardableResult
    mutating func apply(health: HealthBodyStats, untouchedSince saved: FuelSetupDraft?) -> Set<FuelBodyField> {
        let before = self
        var locked = applyAll(health: health)
        guard let saved else {
            return locked
        }
        if before.weightKg != saved.weightKg { weightKg = before.weightKg; locked.remove(.weight) }
        if before.heightCm != saved.heightCm { heightCm = before.heightCm; locked.remove(.height) }
        if before.bodyFatPercent != saved.bodyFatPercent { bodyFatPercent = before.bodyFatPercent; locked.remove(.bodyFat) }
        if before.age != saved.age { age = before.age; locked.remove(.age) }
        if before.sex != saved.sex { sex = before.sex; locked.remove(.sex) }
        return locked
    }

    private mutating func applyAll(health: HealthBodyStats) -> Set<FuelBodyField> {
        var locked: Set<FuelBodyField> = []
        if let value = health.weightKg, value > 0 {
            weightKg = value
            locked.insert(.weight)
        }
        if let value = health.heightCm, value > 0 {
            heightCm = value
            locked.insert(.height)
        }
        if let value = health.bodyFatPercent, value > 0, value < 100 {
            bodyFatPercent = value
            locked.insert(.bodyFat)
        }
        if let value = health.age {
            age = value
            locked.insert(.age)
        }
        if let value = health.sex {
            sex = value
            locked.insert(.sex)
        }
        return locked
    }

    // MARK: - Summaries

    static let defaultsSummary = "Not set — we'll use sensible defaults"

    /// One line for the overview card. A required section with no answers
    /// reads "Not set"; an optional one reads the neutral defaults line.
    func summary(for section: FuelSetupSection, unit: WeightUnit = .kg) -> String {
        if !section.isRequired, isUnset(section) {
            return Self.defaultsSummary
        }
        func weight(_ kg: Double) -> String {
            "\(Int(WeightUnit.kg.convert(kg, to: unit).rounded())) \(unit.abbreviation)"
        }
        func clock(_ minutes: Int) -> String {
            RoutineTime.string(minutes) ?? ""
        }
        let parts: [String]
        switch section {
        case .you:
            parts = [
                weightKg.map(weight),
                heightCm.map { "\(Int($0.rounded())) cm" },
                age.map { "\($0) yrs" },
                sex?.displayName,
            ].compactMap { $0 }
        case .goal:
            var items: [String?] = [goal?.displayName]
            if let goal, goal != .maintain, let target = goalWeightKg {
                items.append("to \(weight(target))")
            }
            if let days = trainingDaysPerWeek {
                items.append("\(days) training day\(days == 1 ? "" : "s")")
            }
            parts = items.compactMap { $0 }
        case .meals:
            var items: [String] = []
            if let mealsPerDay {
                items.append("\(mealsPerDay) meals")
            }
            if breakfastSkipped == true {
                items.append("no breakfast")
            }
            if let start = eatingWindowStartMinutes, let end = eatingWindowEndMinutes {
                items.append("\(clock(start))–\(clock(end))")
            }
            parts = items
        case .week:
            let set = routine.days.filter { $0.wakeMinutes != nil }.count
            if set == 0 {
                parts = []
            } else {
                var items = ["\(set) of 7 days set"]
                let training = routine.trainingDaysPerWeek
                if training > 0 {
                    items.append("\(training) training")
                }
                parts = items
            }
        case .food:
            var items = restrictions.sorted { $0.rawValue < $1.rawValue }.map(\.label)
            if !allergies.isEmpty {
                items.append("\(allergies.count) allerg\(allergies.count == 1 ? "y" : "ies")")
            }
            if !dislikedFoods.isEmpty {
                items.append("\(dislikedFoods.count) won't eat")
            }
            if !favoriteFoods.isEmpty {
                items.append("\(favoriteFoods.count) favourite\(favoriteFoods.count == 1 ? "" : "s")")
            }
            if !favoriteCuisines.isEmpty {
                items.append(favoriteCuisines.prefix(2).joined(separator: ", ") + (favoriteCuisines.count > 2 ? " +\(favoriteCuisines.count - 2)" : ""))
            }
            if let spiceLevel {
                items.append("\(spiceLevel.displayName.lowercased()) spice")
            }
            if let breakfastStyle {
                items.append("\(breakfastStyle.displayName.lowercased()) breakfasts")
            }
            if let snacksPerDay {
                items.append(SnackHabit.label(snacksPerDay))
            }
            if let appetite, appetite != .normal {
                items.append(appetite.displayName.lowercased())
            }
            parts = items.isEmpty ? ["Eats everything"] : items
        case .cooking:
            var items: [String?] = [cookingSkill?.displayName]
            if let days = cookableDaysPerWeek {
                items.append("cooks \(days) day\(days == 1 ? "" : "s")")
            }
            if let minutes = cookMinutesWeekday {
                items.append("\(minutes) min weekdays")
            }
            let owned = equipment.values.filter { $0 }.count
            if !equipment.isEmpty {
                items.append("\(owned) appliance\(owned == 1 ? "" : "s")")
            }
            parts = items.compactMap { $0 }
        case .shopping:
            var items: [String] = []
            if let budget = weeklyBudgetUSD {
                items.append("$\(budget)/week")
            }
            if !stores.isEmpty {
                items.append(stores.prefix(2).joined(separator: ", "))
            }
            parts = items
        case .recovery:
            parts = [recoveryAdjusted ? "Meals follow your recovery" : "Same meals every day"]
        }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }
}

// MARK: - FuelFlowStep

/// One question screen inside a section flow. Related small questions share a
/// screen (weight + height + age, meals + breakfast, the cook times, ...).
enum FuelFlowStep: String, Sendable {
    case healthBody
    /// Weight, height and age (whichever Health doesn't supply) on one screen.
    case bodyStats
    case sex, bodyFat
    case goal, goalTarget, trainingDays
    /// Meals a day and breakfast.
    case meals
    case window
    case weekDays, places, notes
    /// Diet rules and allergies.
    case restrictions
    /// "Never serve me" and "sick of these".
    case wontEat
    /// Foods and cuisines you love.
    case favourites
    /// Spice level and breakfast style.
    case tastes
    /// Snacks and portion size.
    case appetite
    case skill
    /// Days you cook and the minutes on weekdays and weekends.
    case cookTimes
    case leftovers, equipment, clearSkin
    /// Weekly budget and stores.
    case shopping
    case recovery

    /// The screens of `section`, in order, for this draft. Body stats Health
    /// supplies are shown once (read-only); only the missing ones get a
    /// question. A maintain goal skips the target screen.
    static func steps(for section: FuelSetupSection, draft: FuelSetupDraft, locked: Set<FuelBodyField> = []) -> [FuelFlowStep] {
        switch section {
        case .you:
            var steps: [FuelFlowStep] = []
            if !locked.isEmpty {
                steps.append(.healthBody)
            }
            if [FuelBodyField.weight, .height, .age].contains(where: { !locked.contains($0) }) {
                steps.append(.bodyStats)
            }
            if !locked.contains(.sex) {
                steps.append(.sex)
            }
            if !locked.contains(.bodyFat) {
                steps.append(.bodyFat)
            }
            return steps
        case .goal:
            return draft.goal == .maintain || draft.goal == nil ? [.goal, .trainingDays] : [.goal, .goalTarget, .trainingDays]
        case .meals: return [.meals, .window]
        case .week: return [.weekDays, .places, .notes]
        case .food: return [.restrictions, .wontEat, .favourites, .tastes, .appetite]
        case .cooking: return [.skill, .cookTimes, .leftovers, .equipment, .clearSkin]
        case .shopping: return [.shopping]
        case .recovery: return [.recovery]
        }
    }

    /// Optional questions get a "Skip" button and never block the flow.
    /// Only the required answers (body stats, sex, goal, meals) do.
    var isOptional: Bool {
        switch self {
        case .bodyStats, .sex, .goal, .meals, .healthBody: false
        default: true
        }
    }

    /// Whether the screen's answer is good enough to go on. Optional screens
    /// are always fine; required ones need a value; the eating window needs
    /// its last meal after its first (or no window at all).
    func isValid(in draft: FuelSetupDraft, locked: Set<FuelBodyField> = []) -> Bool {
        switch self {
        case .bodyStats:
            (locked.contains(.weight) || (draft.weightKg ?? 0) > 0)
                && (locked.contains(.height) || (draft.heightCm ?? 0) > 0)
                && (locked.contains(.age) || (draft.age ?? 0) > 0)
        case .sex: draft.sex != nil
        case .goal: draft.goal != nil
        case .meals: draft.mealsPerDay != nil
        case .window:
            switch (draft.eatingWindowStartMinutes, draft.eatingWindowEndMinutes) {
            case (nil, nil): true
            case let (start?, end?): end > start
            default: false
            }
        default: true
        }
    }
}

// MARK: - Eating window pacing

extension FuelSetupDraft {
    /// "About every 3 h 30 min" between meals for the current count and
    /// window, so the user sees what their answers mean. nil without both.
    var mealSpacingText: String? {
        guard let meals = mealsPerDay, meals > 1,
              let start = eatingWindowStartMinutes, let end = eatingWindowEndMinutes, end > start
        else {
            return nil
        }
        let gap = (end - start) / (meals - 1)
        let hours = gap / 60
        let minutes = gap % 60
        switch (hours, minutes) {
        case (0, _): return "About every \(minutes) min"
        case (_, 0): return "About every \(hours) h"
        default: return "About every \(hours) h \(minutes) min"
        }
    }
}

// MARK: - FuelSetupProgress

/// Which optional sections the user has already looked at (saved, or skipped
/// on purpose), so "Finish setup" stops offering them. Stored on the device.
enum FuelSetupProgress {
    static let key = "fuelSetup.reviewedSections"

    static func reviewed(defaults: UserDefaults = .standard) -> Set<FuelSetupSection> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(FuelSetupSection.init(rawValue:)))
    }

    static func markReviewed(_ section: FuelSetupSection, defaults: UserDefaults = .standard) {
        var current = reviewed(defaults: defaults)
        current.insert(section)
        defaults.set(current.map(\.rawValue).sorted(), forKey: key)
    }
}
