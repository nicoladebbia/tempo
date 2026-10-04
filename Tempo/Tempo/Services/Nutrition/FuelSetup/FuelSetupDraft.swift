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
    /// Foods the user is tired of (planner rotates them down, not out).
    var boredOfFoods: [String] = []
    /// Low-GI / low-dairy skin focus (`ClearSkinFocusSetting`).
    var clearSkinFocus = false

    // Optional personalisation (the planner reads these; nil / empty = no preference)
    var favoriteCuisines: [String] = []
    var spiceLevel: SpiceLevel?
    var breakfastStyle: BreakfastStyle?
    /// Standalone snacks a day (0...2).
    var snacksPerDay: Int?
    var appetite: AppetiteSize?

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
    /// Appliances at home, `KitchenApplianceKind.rawValue` → owned. Empty
    /// until loaded; the planner only programs recipes these can make.
    var equipment: [String: Bool] = [:]
    /// Shift fuel toward training days using recovery data (permanent
    /// default; the plan wizard can override it for one week).
    var recoveryAdjusted = false

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
        case meals

        var label: String {
            switch self {
            case .weight: "weight"
            case .height: "height"
            case .age: "age"
            case .sex: "sex"
            case .goal: "goal"
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
            case .meals: "How many meals a day do you want — and do you eat breakfast?"
            }
        }
    }

    /// What the planner can't work without: the REQUIRED sections only
    /// (You, Goal, Meals). Everything else is optional and has defaults.
    /// Asked as follow-ups.
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
        // Not on the wire: the AI can't see or change these, keep ours.
        out.boredOfFoods = boredOfFoods
        out.clearSkinFocus = clearSkinFocus
        out.equipment = equipment
        out.recoveryAdjusted = recoveryAdjusted
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
            draft.boredOfFoods = profile.boredOfFoods
            draft.favoriteCuisines = profile.favoriteCuisines
            draft.spiceLevel = profile.spiceLevel
            draft.breakfastStyle = profile.breakfastStyle
            draft.snacksPerDay = profile.snacksPerDay
            draft.appetite = profile.appetite
            draft.cookingSkill = profile.cookingSkill
            draft.trainingDaysPerWeek = profile.trainingFrequency
        }
        if let daily {
            draft.breakfastSkipped = daily.breakfastSkipped
            draft.eatingWindowStartMinutes = daily.eatingWindowStartMinutes
            draft.eatingWindowEndMinutes = daily.eatingWindowEndMinutes
            // The planner's window wins when it differs (wizard / AI Meals
            // settings saved one) — the editor shows what the planner uses.
            if let settings, MealPlanIntake.hasPersistedEatingWindow(settings) {
                let used = MealPlanIntake.seeded(settings: settings, dailyPlan: daily).eatingWindow
                if MealPlanIntake.eatingWindow(fromOnboarding: daily) != used {
                    draft.eatingWindowStartMinutes = used.firstMealHour * 60
                    draft.eatingWindowEndMinutes = used.lastMealHour * 60
                }
            }
            if let routine = daily.weeklyRoutine {
                draft.routine = routine
                draft.notes = daily.fuelSetupNotes ?? ""
            }
        }
        if let settings {
            // One "won't eat" list: fold in the retired AI Meals exclusions.
            if MealPlanIntake.migrateLegacyExclusions(settings: settings, profile: profile) {
                draft.dislikedFoods = profile?.dislikedFoods ?? draft.dislikedFoods
                try? context.save()
            } else if profile == nil {
                // No profile yet, so nothing was migrated: show the legacy list
                // in the draft, because save() clears it and would lose it.
                draft.dislikedFoods = MealPlanIntake.mergedFoods(
                    draft.dislikedFoods,
                    MealPlanIntake.legacyExclusions(settings: settings)
                )
            }
            draft.recoveryAdjusted = settings.mealIntakeRecoveryAdjusted
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
        let rows = (try? context.fetch(FetchDescriptor<KitchenEquipment>())) ?? []
        for kind in KitchenApplianceKind.allCases {
            draft.equipment[kind.rawValue] = rows.first { $0.kindRaw == kind.rawValue }?.isAvailable ?? kind.seededAvailable
        }
        draft.clearSkinFocus = ClearSkinFocusSetting.resolve(modelContext: context)
        return draft
    }

    /// Plan generation's gate: what REQUIRED setup (You, Goal, Meals) is still
    /// missing in the stores, as one sentence; nil when it can go ahead. Reads
    /// only (no migration, no writes), so it is safe to call from a view body.
    @MainActor
    static func requiredMissingMessage(in context: ModelContext) -> String? {
        var draft = FuelSetupDraft()
        if let profile = (try? context.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first {
            draft.weightKg = profile.currentWeightKg
            draft.heightCm = profile.heightCm
            draft.age = profile.age
            draft.sex = profile.biologicalSex
            draft.goal = profile.primaryGoal
        }
        if let daily = UserDailyPlanProfile.current(in: context) {
            draft.breakfastSkipped = daily.breakfastSkipped
            draft.eatingWindowStartMinutes = daily.eatingWindowStartMinutes
        }
        draft.mealsPerDay = MealPlanGeneratorService.fetchUserSettings(modelContext: context)?.mealsPerDayPreference
        return draft.requiredMissingMessage
    }

    /// Write every answer to the store its readers use, then announce the
    /// change so the meal plan follows (ContentView's debounced handler).
    @discardableResult
    @MainActor
    func save(to context: ModelContext, now: Date = Date()) -> Set<FuelSetupSection> {
        save(sections: Set(FuelSetupSection.allCases), to: context, now: now)
    }

    /// A first profile needs the body and goal answers; without them the model
    /// would fall back to made-up defaults (75 kg / 175 cm / 22 / male).
    var canCreateProfile: Bool {
        weightKg != nil && heightCm != nil && age != nil && sex != nil && goal != nil
    }

    /// Writes ONLY the given sections' answers — through the same stores and
    /// rules as the full save, so editing "Food" never rewrites the routine or
    /// the budget — and posts `.tempoDietaryProfileChanged` once.
    ///
    /// Returns the sections that were actually stored. Sections that live on
    /// the DietaryProfile (You, Goal, Food, and Cooking's skill) are NOT stored while no
    /// profile exists and this draft can't create one (`canCreateProfile`);
    /// they stay in the draft until it can.
    @discardableResult
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func save(sections requested: Set<FuelSetupSection>, to context: ModelContext, now: Date = Date()) -> Set<FuelSetupSection> {
        var sections = requested
        func has(_ section: FuelSetupSection) -> Bool {
            sections.contains(section)
        }
        let needsProfile = has(.you) || has(.goal) || has(.food) || has(.cooking)
        let existingProfile = (try? context.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first
        if existingProfile == nil {
            if needsProfile, canCreateProfile {
                // Born with real body and goal answers, never model defaults.
                sections.formUnion([.you, .goal])
            } else {
                sections.subtract([.you, .goal, .food])
            }
        }
        let profile: DietaryProfile? = existingProfile ?? {
            guard needsProfile, canCreateProfile else {
                return nil
            }
            let new = DietaryProfile()
            context.insert(new)
            return new
        }()
        if let profile {
            if has(.you) {
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
            }
            if has(.goal), let goal {
                profile.primaryGoal = goal
                profile.goalWeightKg = goal == .maintain ? nil : goalWeightKg
                profile.weeklyRateKg = goal == .maintain ? nil : weeklyRateKg
            }
            if has(.food) {
                for restriction in DietRestriction.allCases {
                    profile.set(restriction, restrictions.contains(restriction))
                }
                profile.allergies = allergies
                profile.dislikedFoods = dislikedFoods
                profile.favoriteFoods = favoriteFoods
                profile.boredOfFoods = boredOfFoods
                profile.favoriteCuisines = favoriteCuisines
                profile.spiceLevel = spiceLevel
                profile.breakfastStyle = breakfastStyle
                profile.snacksPerDay = snacksPerDay
                profile.appetite = appetite
            }
            if has(.cooking), let cookingSkill {
                profile.cookingSkill = cookingSkill
            }
            if has(.goal) {
                profile.trainingFrequency = trainingDaysPerWeek
                    ?? (has(.week) && routine.trainingDaysPerWeek > 0 ? routine.trainingDaysPerWeek : profile.trainingFrequency)
            } else if has(.week), trainingDaysPerWeek == nil, routine.trainingDaysPerWeek > 0 {
                profile.trainingFrequency = routine.trainingDaysPerWeek
            }
            profile.updatedAt = now
        }

        var daily: UserDailyPlanProfile?
        if has(.meals) || has(.week) {
            let row = UserDailyPlanProfile.current(in: context) ?? {
                let new = UserDailyPlanProfile()
                context.insert(new)
                return new
            }()
            daily = row
            if has(.week), let wake = routine.typicalWakeMinutes {
                row.wakeTimeMinutes = wake
            }
            if has(.meals) {
                if let breakfastSkipped {
                    row.breakfastSkipped = breakfastSkipped
                }
                if let start = eatingWindowStartMinutes, let end = eatingWindowEndMinutes, end > start {
                    row.eatingWindowStartMinutes = start
                    row.eatingWindowEndMinutes = end
                    row.eatingWindowPreset = .custom
                }
            }
            if has(.week) {
                row.weeklyRoutine = routine
                row.fuelSetupNotes = notes.isEmpty ? nil : notes
            }
            row.updatedAt = now
        }

        if let settings = MealPlanGeneratorService.fetchUserSettings(modelContext: context) {
            if has(.week) {
                if let wake = routine.typicalWakeMinutes {
                    settings.wakeTimeMinutes = wake
                }
                if let bed = routine.typicalBedMinutes {
                    settings.bedtimeTargetMinutes = bed
                }
            }
            if has(.meals) {
                settings.mealsPerDayPreference = mealsPerDay ?? settings.mealsPerDayPreference
                if let daily, let start = eatingWindowStartMinutes, let end = eatingWindowEndMinutes {
                    let window = EatingWindow(firstMealHour: Int((Double(start) / 60).rounded(.up)), lastMealHour: min(23, end / 60))
                    if window.isValid {
                        MealPlanIntake.saveEatingWindow(window, settings: settings, dailyPlan: daily)
                    }
                }
            }
            if has(.cooking) {
                settings.cookTimeWeekdayMins = cookMinutesWeekday ?? settings.cookTimeWeekdayMins
                settings.cookTimeWeekendMins = cookMinutesWeekend ?? settings.cookTimeWeekendMins
                // Clear only the "this week" answer this save supersedes, so the
                // rest of the week's wizard answers (skipped foods, the other
                // toggle) survive. A temp value that differs from what was just
                // saved would otherwise keep winning.
                if let cookableDaysPerWeek, cookableDaysPerWeek != settings.mealIntakeCookableDays {
                    settings.mealIntakeTempCookableDays = nil
                }
                settings.mealIntakeCookableDays = cookableDaysPerWeek ?? settings.mealIntakeCookableDays
                if let leftoverTolerance {
                    settings.mealIntakeLeftoverToleranceRaw = leftoverTolerance.rawValue
                }
            }
            if has(.recovery) {
                if recoveryAdjusted != settings.mealIntakeRecoveryAdjusted {
                    settings.mealIntakeTempRecoveryAdjusted = recoveryAdjusted
                }
                settings.mealIntakeRecoveryAdjusted = recoveryAdjusted
            }
            if has(.food) {
                // "Won't eat" has one home (DietaryProfile.dislikedFoods, above);
                // the retired AI Meals list must not come back.
                settings.mealIntakeExclusionsRaw = ""
            }
            if has(.shopping) {
                settings.groceryBudgetCapUSD = weeklyBudgetUSD ?? settings.groceryBudgetCapUSD
                if !stores.isEmpty {
                    settings.groceryPreferredStores = stores
                }
            }
            settings.updatedAt = now
        }

        if has(.cooking) {
            if !equipment.isEmpty {
                let rows = (try? context.fetch(FetchDescriptor<KitchenEquipment>())) ?? []
                for kind in KitchenApplianceKind.allCases {
                    guard let owned = equipment[kind.rawValue] else {
                        continue
                    }
                    if let row = rows.first(where: { $0.kindRaw == kind.rawValue }) {
                        if row.isAvailable != owned {
                            row.isAvailable = owned
                            row.updatedAt = now
                        }
                    } else {
                        context.insert(KitchenEquipment(kind: kind, isAvailable: owned, updatedAt: now))
                    }
                }
            }
            ClearSkinFocusSetting.setEnabled(clearSkinFocus)
        }

        try? context.save()
        NotificationCenter.default.post(name: .tempoDietaryProfileChanged, object: nil)
        // Cooking's kitchen answers live in settings, but its skill needs the profile.
        if profile == nil, cookingSkill != nil {
            sections.remove(.cooking)
        }
        return sections
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
