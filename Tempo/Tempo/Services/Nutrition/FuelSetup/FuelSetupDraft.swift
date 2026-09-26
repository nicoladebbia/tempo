//
// FuelSetupDraft.swift
// Tempo
//
// Everything the single Fuel setup captures, in one value: body, goal, diet
// rules, food likes, eating pattern, cooking, shopping and the weekly
// routine. Loaded from — and saved back to — the stores the rest of the app
// already reads (DietaryProfile, UserDailyPlanProfile, UserSettings), so the
// planner, day plan, reminders and targets all see the same answers.
//

import Foundation
import SwiftData

// MARK: - FuelSetupDraft

struct FuelSetupDraft: Equatable, Sendable {
    // Body
    var weightKg: Double?
    var heightCm: Double?
    var age: Int?
    var sex: BiologicalSex?
    var bodyFatPercent: Double?

    // Goal
    var goal: DietaryGoal?
    var goalWeightKg: Double?
    var weeklyRateKg: Double?

    // Diet rules
    var restrictions: Set<DietRestriction> = []
    var allergies: [String] = []
    var dislikedFoods: [String] = []
    var favoriteFoods: [String] = []

    // Eating pattern
    var mealsPerDay: Int?
    var breakfastSkipped: Bool?
    var eatingWindowStartMinutes: Int?
    var eatingWindowEndMinutes: Int?

    // Cooking
    var cookingSkill: CookingSkill?
    var cookMinutesWeekday: Int?
    var cookMinutesWeekend: Int?
    var cookableDaysPerWeek: Int?
    var leftoverTolerance: LeftoverTolerance?

    // Shopping
    var weeklyBudgetUSD: Int?
    var stores: [String] = []

    /// Training
    var trainingDaysPerWeek: Int?

    /// Week
    var routine = WeeklyRoutine.empty

    /// Anything else the user said that a planner should know
    /// ("I get bored of chicken fast", "Sunday is family lunch").
    var notes: String = ""

    // MARK: - Completeness

    enum Field: String, CaseIterable, Sendable {
        case weight
        case height
        case age
        case sex
        case goal
        case wakeTime
        case meals

        var label: String {
            switch self {
            case .weight: "weight"
            case .height: "height"
            case .age: "age"
            case .sex: "sex"
            case .goal: "goal"
            case .wakeTime: "wake-up time"
            case .meals: "meals a day"
            }
        }

        var question: String {
            switch self {
            case .weight: "How much do you weigh?"
            case .height: "How tall are you?"
            case .age: "How old are you?"
            case .sex: "Male or female (for the calorie formula)?"
            case .goal: "What's the goal — lose fat, maintain, or gain muscle?"
            case .wakeTime: "What time do you usually wake up on weekdays?"
            case .meals: "How many meals a day do you want — and do you eat breakfast?"
            }
        }
    }

    /// What the planner can't work without. Asked as follow-ups.
    var missingFields: [Field] {
        var missing: [Field] = []
        if weightKg == nil {
            missing.append(.weight)
        }
        if heightCm == nil {
            missing.append(.height)
        }
        if age == nil {
            missing.append(.age)
        }
        if sex == nil {
            missing.append(.sex)
        }
        if goal == nil {
            missing.append(.goal)
        }
        if routine.typicalWakeMinutes == nil {
            missing.append(.wakeTime)
        }
        if mealsPerDay == nil, breakfastSkipped == nil, eatingWindowStartMinutes == nil {
            missing.append(.meals)
        }
        return missing
    }

    var isComplete: Bool {
        missingFields.isEmpty
    }

    // MARK: - Adopt an AI update

    /// The AI saw this draft as CURRENT and returned the complete updated
    /// profile, so its values replace ours, removals (null / []) included —
    /// "I eat gluten again" must clear gluten-free. Only what the wire can't
    /// carry survives from here: place ids and coordinates, and whole days the
    /// AI left out (`returnedDays`, Mon=1).
    func adopting(_ updated: FuelSetupDraft, returnedDays: Set<Int>) -> FuelSetupDraft {
        var out = updated
        out.routine = routine.adopting(updated.routine, returnedDays: returnedDays)
        return out
    }
}

// MARK: - DietRestriction

enum DietRestriction: String, CaseIterable, Codable, Sendable, Identifiable {
    case lactoseFree
    case glutenFree
    case vegetarian
    case vegan
    case halal
    case nutFree
    case shellfishAllergy
    case noAddedSugars
    case noCoffee

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .lactoseFree: "Lactose-free"
        case .glutenFree: "Gluten-free"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .halal: "Halal"
        case .nutFree: "Nut allergy"
        case .shellfishAllergy: "Shellfish allergy"
        case .noAddedSugars: "No added sugar"
        case .noCoffee: "No coffee"
        }
    }
}

// MARK: - Routine adopt

extension WeeklyRoutine {
    /// A returned day replaces ours entirely (no events = none); a day the AI
    /// left out keeps ours. Places match by name (case-insensitive) so ids and
    /// coordinates survive; a place the AI dropped stays only while a kept
    /// day still points at it.
    func adopting(_ updated: WeeklyRoutine, returnedDays: Set<Int>) -> WeeklyRoutine {
        var out = updated
        for weekday in 1 ... 7 where !returnedDays.contains(weekday) {
            out[weekday] = self[weekday]
        }
        for index in out.places.indices {
            let place = out.places[index]
            guard let old = places.first(where: { $0.name.caseInsensitiveCompare(place.name) == .orderedSame }) else {
                continue
            }
            out.places[index].id = old.id
            out.places[index].latitude = place.latitude ?? old.latitude
            out.places[index].longitude = place.longitude ?? old.longitude
            out.places[index].address = place.address ?? old.address
            out.remapPlace(from: place.id, to: old.id)
        }
        let referenced = Set(out.days.flatMap(\.events).compactMap(\.placeID))
        for old in places where referenced.contains(old.id) && !out.places.contains(where: { $0.id == old.id }) {
            out.places.append(old)
        }
        return out
    }

    private mutating func remapPlace(from old: UUID, to new: UUID) {
        for index in days.indices {
            for eventIndex in days[index].events.indices where days[index].events[eventIndex].placeID == old {
                days[index].events[eventIndex].placeID = new
            }
        }
    }
}

// MARK: - Load / save

extension FuelSetupDraft {
    /// Today's answers from every store (so editing starts from what's saved).
    @MainActor
    static func load(from context: ModelContext) -> FuelSetupDraft {
        var draft = FuelSetupDraft()
        let profile = (try? context.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first
        let daily = UserDailyPlanProfile.current(in: context)
        let settings = MealPlanGeneratorService.fetchUserSettings(modelContext: context)

        if let profile {
            draft.weightKg = profile.currentWeightKg
            draft.heightCm = profile.heightCm
            draft.age = profile.age
            draft.sex = profile.biologicalSex
            draft.bodyFatPercent = profile.bodyFatPercent
            draft.goal = profile.primaryGoal
            draft.goalWeightKg = profile.goalWeightKg
            draft.weeklyRateKg = profile.weeklyRateKg
            draft.restrictions = Set(DietRestriction.allCases.filter { profile.has($0) })
            draft.allergies = profile.allergies
            draft.dislikedFoods = profile.dislikedFoods
            draft.favoriteFoods = profile.favoriteFoods
            draft.cookingSkill = profile.cookingSkill
            draft.trainingDaysPerWeek = profile.trainingFrequency
        }
        if let daily {
            draft.breakfastSkipped = daily.breakfastSkipped
            draft.eatingWindowStartMinutes = daily.eatingWindowStartMinutes
            draft.eatingWindowEndMinutes = daily.eatingWindowEndMinutes
            if let routine = daily.weeklyRoutine {
                draft.routine = routine
                draft.notes = daily.fuelSetupNotes ?? ""
            }
        }
        if let settings {
            draft.mealsPerDay = settings.mealsPerDayPreference
            draft.cookMinutesWeekday = settings.cookTimeWeekdayMins
            draft.cookMinutesWeekend = settings.cookTimeWeekendMins
            draft.cookableDaysPerWeek = settings.mealIntakeCookableDays
            draft.leftoverTolerance = settings.mealIntakeLeftoverToleranceRaw.flatMap(LeftoverTolerance.init(rawValue:))
            draft.weeklyBudgetUSD = settings.groceryBudgetCapUSD
            draft.stores = settings.groceryPreferredStores
            if draft.routine.typicalWakeMinutes == nil, daily?.weeklyRoutine == nil {
                // Seed the week from the single wake/bed time onboarding asked for.
                let wake = daily?.wakeTimeMinutes ?? settings.wakeTimeMinutes
                for weekday in 1 ... 7 {
                    draft.routine[weekday].wakeMinutes = wake
                    draft.routine[weekday].bedMinutes = settings.bedtimeTargetMinutes
                }
            }
        }
        return draft
    }

    /// Write every answer to the store its readers use, then announce the
    /// change so the meal plan follows (ContentView's debounced handler).
    @MainActor
    func save(to context: ModelContext, now: Date = Date()) {
        let profile = (try? context.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first
            ?? {
                let new = DietaryProfile()
                context.insert(new)
                return new
            }()
        if let weightKg {
            profile.currentWeightKg = weightKg
        }
        if let heightCm {
            profile.heightCm = heightCm
        }
        if let age {
            profile.age = age
        }
        if let sex {
            profile.biologicalSex = sex
        }
        profile.bodyFatPercent = bodyFatPercent
        if let goal {
            profile.primaryGoal = goal
            profile.goalWeightKg = goal == .maintain ? nil : goalWeightKg
            profile.weeklyRateKg = goal == .maintain ? nil : weeklyRateKg
        }
        for restriction in DietRestriction.allCases {
            profile.set(restriction, restrictions.contains(restriction))
        }
        profile.allergies = allergies
        profile.dislikedFoods = dislikedFoods
        profile.favoriteFoods = favoriteFoods
        if let cookingSkill {
            profile.cookingSkill = cookingSkill
        }
        profile
            .trainingFrequency = trainingDaysPerWeek ??
            (routine.trainingDaysPerWeek > 0 ? routine.trainingDaysPerWeek : profile.trainingFrequency)
        profile.updatedAt = now

        let daily = UserDailyPlanProfile.current(in: context) ?? {
            let new = UserDailyPlanProfile()
            context.insert(new)
            return new
        }()
        if let wake = routine.typicalWakeMinutes {
            daily.wakeTimeMinutes = wake
        }
        if let breakfastSkipped {
            daily.breakfastSkipped = breakfastSkipped
        }
        if let start = eatingWindowStartMinutes, let end = eatingWindowEndMinutes, end > start {
            daily.eatingWindowStartMinutes = start
            daily.eatingWindowEndMinutes = end
            daily.eatingWindowPreset = .custom
        }
        daily.weeklyRoutine = routine
        daily.fuelSetupNotes = notes.isEmpty ? nil : notes
        daily.updatedAt = now

        if let settings = MealPlanGeneratorService.fetchUserSettings(modelContext: context) {
            if let wake = routine.typicalWakeMinutes {
                settings.wakeTimeMinutes = wake
            }
            if let bed = routine.typicalBedMinutes {
                settings.bedtimeTargetMinutes = bed
            }
            settings.mealsPerDayPreference = mealsPerDay ?? settings.mealsPerDayPreference
            settings.cookTimeWeekdayMins = cookMinutesWeekday ?? settings.cookTimeWeekdayMins
            settings.cookTimeWeekendMins = cookMinutesWeekend ?? settings.cookTimeWeekendMins
            settings.mealIntakeCookableDays = cookableDaysPerWeek ?? settings.mealIntakeCookableDays
            if let leftoverTolerance {
                settings.mealIntakeLeftoverToleranceRaw = leftoverTolerance.rawValue
            }
            if let start = eatingWindowStartMinutes, let end = eatingWindowEndMinutes {
                let window = EatingWindow(firstMealHour: Int((Double(start) / 60).rounded(.up)), lastMealHour: min(23, end / 60))
                if window.isValid {
                    settings.mealIntakeFirstMealHour = window.firstMealHour
                    settings.mealIntakeLastMealHour = window.lastMealHour
                }
            }
            settings.groceryBudgetCapUSD = weeklyBudgetUSD ?? settings.groceryBudgetCapUSD
            if !stores.isEmpty {
                settings.groceryPreferredStores = stores
            }
            settings.updatedAt = now
        }

        try? context.save()
        NotificationCenter.default.post(name: .tempoDietaryProfileChanged, object: nil)
    }
}

// MARK: - DietaryProfile ↔ DietRestriction

extension DietaryProfile {
    func has(_ restriction: DietRestriction) -> Bool {
        switch restriction {
        case .lactoseFree: isLactoseFree
        case .glutenFree: isGlutenFree
        case .vegetarian: isVegetarian
        case .vegan: isVegan
        case .halal: isHalal
        case .nutFree: isNutFree
        case .shellfishAllergy: isShellFishAllergy
        case .noAddedSugars: avoidAddedSugars
        case .noCoffee: noCoffee
        }
    }

    func set(_ restriction: DietRestriction, _ on: Bool) {
        switch restriction {
        case .lactoseFree: isLactoseFree = on
        case .glutenFree: isGlutenFree = on
        case .vegetarian: isVegetarian = on
        case .vegan: isVegan = on
        case .halal: isHalal = on
        case .nutFree: isNutFree = on
        case .shellfishAllergy: isShellFishAllergy = on
        case .noAddedSugars: avoidAddedSugars = on
        case .noCoffee: noCoffee = on
        }
    }
}
