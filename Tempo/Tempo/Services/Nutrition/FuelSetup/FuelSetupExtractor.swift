//
// FuelSetupExtractor.swift
// Tempo
//
// Fuel setup's "talk me through your week": the user speaks (or types) for
// as long as they like; Claude Sonnet, through the Pro-gated nutrition AI
// proxy, turns it into a FuelSetupDraft plus a few follow-up questions for
// whatever the planner still needs. Follow-up answers go through the same
// call with the current draft; the AI returns the whole updated profile, so
// a spoken correction or removal ("no more gluten-free") sticks.
//

import Foundation

// MARK: - FuelSetupExtraction

struct FuelSetupExtraction: Equatable, Sendable {
    var draft: FuelSetupDraft
    /// Short questions about what's still unclear, in the user's language.
    var followUps: [String]
    /// Weekdays (Mon=1) the AI returned; the rest keep what we had.
    var returnedDays: Set<Int> = []
}

// MARK: - FuelSetupExtractor

enum FuelSetupExtractor {
    static let systemPrompt = """
    You turn a person's description of their life and week (spoken or typed, \
    English or Italian, often rambling) into a structured nutrition + routine \
    profile for a meal planner. Return ONLY valid JSON, no prose, no code fences.

    You get CURRENT (what we already know, JSON) and NEW (what they just said). \
    Return the COMPLETE updated profile: keep CURRENT values unless NEW changes \
    them; add everything NEW mentions. Never invent facts — use null / [] for \
    anything not said or clearly implied.

    Shape:
    {"profile":{
      "weightKg":<n|null>,"heightCm":<n|null>,"age":<int|null>,"sex":"male|female|null",
      "bodyFatPercent":<n|null>,"goal":"cut|maintain|leanGain|null",
      "goalWeightKg":<n|null>,"weeklyRateKg":<n|null>,
      "restrictions":["lactoseFree|glutenFree|vegetarian|vegan|halal|nutFree|shellfishAllergy|noAddedSugars|noCoffee"],
      "allergies":[".."],"dislikedFoods":[".."],"favoriteFoods":[".."],
      "mealsPerDay":<int|null>,"breakfastSkipped":<bool|null>,
      "eatingWindowStart":"HH:mm|null","eatingWindowEnd":"HH:mm|null",
      "cookingSkill":"beginner|intermediate|advanced|null",
      "cookMinutesWeekday":<int|null>,"cookMinutesWeekend":<int|null>,
      "cookableDaysPerWeek":<int 0-7|null>,
      "leftoverTolerance":"freshDaily|twoToThreeDayBatches|fullWeekPrep|null",
      "weeklyBudgetUSD":<int|null>,"stores":[".."],"trainingDaysPerWeek":<int|null>,
      "places":[{"name":"FIU Modesto Maidique Campus","address":"..|null","usualRestaurants":["Panera Bread"]}],
      "days":[{"day":"mon|tue|wed|thu|fri|sat|sun",
        "wake":"HH:mm|null","leaveHome":"HH:mm|null","backHome":"HH:mm|null","bed":"HH:mm|null",
        "training":{"start":"HH:mm","durationMinutes":<int>,"kind":"gym - upper"}|null,
        "events":[{"kind":"classOrWork|mealOut|other","title":"Class","start":"HH:mm","end":"HH:mm|null",
          "place":"<a places[].name>|null","with":"friends|null","restaurants":["Panera Bread"]}]}],
      "notes":"<other planner-relevant facts, one short paragraph, or empty>"},
     "followUps":["<question>"]}

    Rules:
    - Convert pounds → kg, feet/inches → cm. 24h times. "Weekdays" = mon-fri.
    - A meal eaten out at a fixed time (e.g. lunch with friends at 13:00 after \
    class) is an event of kind mealOut at that place, with the restaurants they \
    mentioned (usual one first). Also add those restaurants to the place's usualRestaurants.
    - Give classes/work the place they happen at when it's clear (e.g. all their \
    classes are at the campus they named).
    - notes: only planner-relevant facts that fit NO field above (e.g. "family \
    lunch on Sundays", "gets bored of chicken"). Don't repeat fields; empty if none.
    - days: return every day that has anything in CURRENT or NEW. A day you \
    return replaces that day entirely (so to cancel something, return the day \
    without it); a day you leave out keeps CURRENT.
    - To remove something (a restriction, a place, a training slot), leave it \
    out of what you return.
    - followUps: at most 5, only for things a weekly meal planner truly needs and \
    that are missing or ambiguous (body stats, goal, wake times, training times, \
    where they eat lunch, meals per day). Ask in the language they used. \
    Empty list if nothing important is missing.
    """

    @MainActor
    static func extract(
        said text: String,
        current: FuelSetupDraft,
        apiClient: APIClient
    ) async throws -> FuelSetupExtraction {
        let body = NutritionProxyTextRequest(
            model: "sonnet",
            system: systemPrompt,
            userMessage: userMessage(said: text, current: current),
            maxTokens: 6000,
            temperature: 0.1,
            caller: "fuel_setup"
        )
        let response: NutritionProxyTextResponse = try await apiClient.request(.nutritionProxyText(), body: body)
        let extraction = try parse(response.text)
        return FuelSetupExtraction(
            draft: current.adopting(extraction.draft, returnedDays: extraction.returnedDays),
            followUps: extraction.followUps,
            returnedDays: extraction.returnedDays
        )
    }

    static func userMessage(said text: String, current: FuelSetupDraft) -> String {
        let currentJSON = (try? String(data: JSONEncoder.sorted.encode(Wire.Profile(current)), encoding: .utf8)) ?? "{}"
        return "CURRENT:\n\(currentJSON)\n\nNEW:\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case unreadable

        var errorDescription: String? {
            "Couldn't turn that into a profile. Try again, or fill it in below."
        }
    }

    /// The raw extraction (not yet adopted onto the current draft).
    static func parse(_ raw: String) throws -> FuelSetupExtraction {
        guard let json = TrainerProgramParser.extractJSON(from: raw),
              let data = json.data(using: .utf8),
              let wire = try? JSONDecoder().decode(Wire.self, from: data)
        else {
            throw ParseError.unreadable
        }
        return FuelSetupExtraction(
            draft: wire.profile?.draft ?? FuelSetupDraft(),
            followUps: (wire.followUps ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(5).map(\.self),
            returnedDays: wire.profile?.returnedDays ?? []
        )
    }

    /// Friendly message for a failed call.
    static func message(for error: Error) -> String {
        switch error as? APIError {
        case .subscriptionRequired?: "Talking it through uses AI — that's a Pro feature. Fill it in below instead."
        case .aiConsentRequired?: "Allow AI features in Settings to use this, or fill it in below."
        case .unauthorized?: "Sign in to use this, or fill it in below."
        case .networkError?,
             .timeout?,
             .connectionRefused?: "No connection. Try again, or fill it in below."
        default: (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again, or fill it in below."
        }
    }

    // MARK: - Wire format

    struct Wire: Decodable {
        let profile: Profile?
        let followUps: [String]?

        struct Profile: Codable {
            var weightKg: Flex<Double>?
            var heightCm: Flex<Double>?
            var age: Flex<Int>?
            var sex: String?
            var bodyFatPercent: Flex<Double>?
            var goal: String?
            var goalWeightKg: Flex<Double>?
            var weeklyRateKg: Flex<Double>?
            var restrictions: [String]?
            var allergies: [String]?
            var dislikedFoods: [String]?
            var favoriteFoods: [String]?
            var mealsPerDay: Flex<Int>?
            var breakfastSkipped: Bool?
            var eatingWindowStart: String?
            var eatingWindowEnd: String?
            var cookingSkill: String?
            var cookMinutesWeekday: Flex<Int>?
            var cookMinutesWeekend: Flex<Int>?
            var cookableDaysPerWeek: Flex<Int>?
            var leftoverTolerance: String?
            var weeklyBudgetUSD: Flex<Int>?
            var stores: [String]?
            var trainingDaysPerWeek: Flex<Int>?
            var places: [Place]?
            var days: [Day]?
            var notes: String?
        }

        struct Place: Codable {
            var name: String
            var address: String?
            var usualRestaurants: [String]?
        }

        struct Day: Codable {
            var day: String
            var wake: String?
            var leaveHome: String?
            var backHome: String?
            var bed: String?
            var training: Training?
            var events: [Event]?
        }

        struct Training: Codable {
            var start: String?
            var durationMinutes: Flex<Int>?
            var kind: String?
        }

        struct Event: Codable {
            var kind: String?
            var title: String?
            var start: String?
            var end: String?
            var place: String?
            var with: String?
            var restaurants: [String]?
        }
    }

    static let weekdayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
}

// MARK: - Flex

struct Flex<Value: Codable & LosslessStringConvertible & Sendable>: Codable, Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let direct = try? container.decode(Value.self) {
            value = direct
        } else if let double = try? container.decode(Double.self), let converted = Value(String(Int(double.rounded()))) {
            value = converted
        } else if let text = try? container.decode(String.self),
                  let parsed = Value(text.trimmingCharacters(in: .whitespaces)) ?? Double(text)
                  .flatMap({ Value(String(Int($0.rounded()))) })
        {
            value = parsed
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a number")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Wire ↔ Draft

extension FuelSetupExtractor.Wire.Profile {
    init(_ draft: FuelSetupDraft) {
        weightKg = draft.weightKg.map(Flex.init)
        heightCm = draft.heightCm.map(Flex.init)
        age = draft.age.map(Flex.init)
        sex = draft.sex?.rawValue
        bodyFatPercent = draft.bodyFatPercent.map(Flex.init)
        goal = draft.goal?.rawValue
        goalWeightKg = draft.goalWeightKg.map(Flex.init)
        weeklyRateKg = draft.weeklyRateKg.map(Flex.init)
        restrictions = draft.restrictions.map(\.rawValue).sorted()
        allergies = draft.allergies
        dislikedFoods = draft.dislikedFoods
        favoriteFoods = draft.favoriteFoods
        mealsPerDay = draft.mealsPerDay.map(Flex.init)
        breakfastSkipped = draft.breakfastSkipped
        eatingWindowStart = RoutineTime.string(draft.eatingWindowStartMinutes)
        eatingWindowEnd = RoutineTime.string(draft.eatingWindowEndMinutes)
        cookingSkill = draft.cookingSkill?.rawValue
        cookMinutesWeekday = draft.cookMinutesWeekday.map(Flex.init)
        cookMinutesWeekend = draft.cookMinutesWeekend.map(Flex.init)
        cookableDaysPerWeek = draft.cookableDaysPerWeek.map(Flex.init)
        leftoverTolerance = draft.leftoverTolerance?.rawValue
        weeklyBudgetUSD = draft.weeklyBudgetUSD.map(Flex.init)
        stores = draft.stores
        trainingDaysPerWeek = draft.trainingDaysPerWeek.map(Flex.init)
        places = draft.routine.places.map {
            FuelSetupExtractor.Wire.Place(name: $0.name, address: $0.address, usualRestaurants: $0.usualRestaurants)
        }
        days = draft.routine.days.filter { !$0.isEmpty }.map { day in
            FuelSetupExtractor.Wire.Day(
                day: FuelSetupExtractor.weekdayKeys[day.weekday - 1],
                wake: RoutineTime.string(day.wakeMinutes),
                leaveHome: RoutineTime.string(day.leaveHomeMinutes),
                backHome: RoutineTime.string(day.backHomeMinutes),
                bed: RoutineTime.string(day.bedMinutes),
                training: day.training.map {
                    FuelSetupExtractor.Wire.Training(
                        start: RoutineTime.string($0.startMinutes),
                        durationMinutes: Flex($0.durationMinutes),
                        kind: $0.kind
                    )
                },
                events: day.events.map { event in
                    FuelSetupExtractor.Wire.Event(
                        kind: event.kind.rawValue, title: event.title,
                        start: RoutineTime.string(event.startMinutes), end: RoutineTime.string(event.endMinutes),
                        place: draft.routine.place(id: event.placeID)?.name, with: event.with,
                        restaurants: event.restaurants
                    )
                }
            )
        }
        notes = draft.notes.isEmpty ? nil : draft.notes
    }

    var returnedDays: Set<Int> {
        Set((days ?? []).compactMap { day in
            FuelSetupExtractor.weekdayKeys.firstIndex(of: String(day.day.lowercased().prefix(3))).map { $0 + 1 }
        })
    }

    var draft: FuelSetupDraft {
        var draft = FuelSetupDraft()
        draft.weightKg = weightKg?.value.clamped(to: 25 ... 350)
        draft.heightCm = heightCm?.value.clamped(to: 100 ... 250)
        draft.age = age?.value.clamped(to: 10 ... 100)
        draft.sex = sex.flatMap { BiologicalSex(rawValue: $0.lowercased()) }
        draft.bodyFatPercent = bodyFatPercent?.value.clamped(to: 3 ... 60)
        draft.goal = goal.flatMap { raw in DietaryGoal.allCases.first { $0.rawValue.lowercased() == raw.lowercased() } }
        draft.goalWeightKg = goalWeightKg?.value.clamped(to: 25 ... 350)
        draft.weeklyRateKg = weeklyRateKg?.value.clamped(to: 0 ... 1.5)
        draft.restrictions = Set((restrictions ?? []).compactMap(DietRestriction.init(rawValue:)))
        draft.allergies = Self.clean(allergies)
        draft.dislikedFoods = Self.clean(dislikedFoods)
        draft.favoriteFoods = Self.clean(favoriteFoods)
        draft.mealsPerDay = mealsPerDay?.value.clamped(to: 1 ... 8)
        draft.breakfastSkipped = breakfastSkipped
        draft.eatingWindowStartMinutes = RoutineTime.minutes(from: eatingWindowStart)
        draft.eatingWindowEndMinutes = RoutineTime.minutes(from: eatingWindowEnd)
        draft.cookingSkill = cookingSkill.flatMap { CookingSkill(rawValue: $0.lowercased()) }
        draft.cookMinutesWeekday = cookMinutesWeekday?.value.clamped(to: 0 ... 300)
        draft.cookMinutesWeekend = cookMinutesWeekend?.value.clamped(to: 0 ... 300)
        draft.cookableDaysPerWeek = cookableDaysPerWeek?.value.clamped(to: 0 ... 7)
        draft.leftoverTolerance = leftoverTolerance.flatMap(LeftoverTolerance.init(rawValue:))
        draft.weeklyBudgetUSD = weeklyBudgetUSD?.value.clamped(to: 0 ... 5000)
        draft.stores = Self.clean(stores)
        draft.trainingDaysPerWeek = trainingDaysPerWeek?.value.clamped(to: 0 ... 7)
        draft.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var routine = WeeklyRoutine.empty
        for place in places ?? [] where !place.name.trimmingCharacters(in: .whitespaces).isEmpty {
            routine.places.append(RoutinePlace(
                name: place.name.trimmingCharacters(in: .whitespaces),
                address: place.address,
                usualRestaurants: Self.clean(place.usualRestaurants)
            ))
        }
        for day in days ?? [] {
            guard let index = FuelSetupExtractor.weekdayKeys.firstIndex(of: String(day.day.lowercased().prefix(3))) else {
                continue
            }
            let weekday = index + 1
            var routineDay = DayRoutine(weekday: weekday)
            routineDay.wakeMinutes = RoutineTime.minutes(from: day.wake)
            routineDay.leaveHomeMinutes = RoutineTime.minutes(from: day.leaveHome)
            routineDay.backHomeMinutes = RoutineTime.minutes(from: day.backHome)
            routineDay.bedMinutes = RoutineTime.minutes(from: day.bed)
            if let training = day.training, let start = RoutineTime.minutes(from: training.start) {
                routineDay.training = TrainingSlot(
                    startMinutes: start,
                    durationMinutes: training.durationMinutes?.value.clamped(to: 10 ... 300) ?? 60,
                    kind: training.kind ?? ""
                )
            }
            routineDay.events = (day.events ?? []).compactMap { event in
                guard let start = RoutineTime.minutes(from: event.start) else {
                    return nil
                }
                let placeID = event.place.flatMap { name in
                    routine.places.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
                } ?? event.place.flatMap { name -> UUID? in
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else {
                        return nil
                    }
                    let place = RoutinePlace(name: trimmed)
                    routine.places.append(place)
                    return place.id
                }
                let kind = event.kind.flatMap(RoutineEvent.Kind.init(rawValue:)) ?? .other
                return RoutineEvent(
                    kind: kind,
                    title: event.title?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? kind.label,
                    startMinutes: start,
                    endMinutes: RoutineTime.minutes(from: event.end),
                    placeID: placeID,
                    with: event.with?.nilIfEmpty,
                    restaurants: Self.clean(event.restaurants)
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }
            routine[weekday] = routineDay
        }
        // A restaurant eaten at a place belongs on that place's list too.
        for day in routine.days {
            for event in day.events where event.kind == .mealOut {
                guard let index = routine.places.firstIndex(where: { $0.id == event.placeID }) else {
                    continue
                }
                for restaurant in event.restaurants where !routine.places[index].usualRestaurants.contains(where: {
                    $0.caseInsensitiveCompare(restaurant) == .orderedSame
                }) {
                    routine.places[index].usualRestaurants.append(restaurant)
                }
            }
        }
        draft.routine = routine
        return draft
    }

    private static func clean(_ values: [String]?) -> [String] {
        var seen = Set<String>()
        return (values ?? []).compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else {
                return nil
            }
            return trimmed
        }
    }
}

// MARK: - Helpers

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
