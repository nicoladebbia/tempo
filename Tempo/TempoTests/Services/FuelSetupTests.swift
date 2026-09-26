//
// FuelSetupTests.swift
// Tempo
//
// The single Fuel setup: routine time parsing, turning the AI's JSON into
// a draft (meals out at a place, restaurants, lenient numbers), merging
// follow-ups without losing answers, and saving to / loading from the
// stores the rest of the app reads.
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - RoutineTimeTests

final class RoutineTimeTests: XCTestCase {
    func testParsesTwentyFourHourAndAmPm() {
        XCTAssertEqual(RoutineTime.minutes(from: "13:00"), 780)
        XCTAssertEqual(RoutineTime.minutes(from: "7:30"), 450)
        XCTAssertEqual(RoutineTime.minutes(from: "1:05 pm"), 785)
        XCTAssertEqual(RoutineTime.minutes(from: "12am"), 0)
        XCTAssertEqual(RoutineTime.minutes(from: "12 PM"), 720)
        XCTAssertNil(RoutineTime.minutes(from: "25:00"))
        XCTAssertNil(RoutineTime.minutes(from: "lunch"))
        XCTAssertNil(RoutineTime.minutes(from: nil))
        XCTAssertEqual(RoutineTime.string(785), "13:05")
    }

    func testTypicalWakeIsTheCommonWeekdayOne() {
        var routine = WeeklyRoutine.empty
        for weekday in 1 ... 5 {
            routine[weekday].wakeMinutes = weekday == 3 ? 360 : 420
        }
        routine[6].wakeMinutes = 600
        XCTAssertEqual(routine.typicalWakeMinutes, 420)
        XCTAssertEqual(routine.days.count, 7)
    }
}

// MARK: - FuelSetupExtractorTests

final class FuelSetupExtractorTests: XCTestCase {
    /// What Sonnet returns for "Mon and Wed I have class 11–12:15 at FIU MMC,
    /// I wait for my friends and we eat at 1, usually Panera…".
    private let nicolaJSON = """
    Here you go:
    {"profile":{"weightKg":"78.5","heightCm":183,"age":24,"sex":"male","goal":"cut",
    "goalWeightKg":75,"weeklyRateKg":0.4,"restrictions":["lactoseFree","keto"],
    "allergies":[],"dislikedFoods":["mushrooms","Mushrooms"],"favoriteFoods":["pasta"],
    "mealsPerDay":4,"breakfastSkipped":false,"eatingWindowStart":null,"eatingWindowEnd":null,
    "cookingSkill":"intermediate","cookMinutesWeekday":20,"cookMinutesWeekend":null,
    "cookableDaysPerWeek":5,"leftoverTolerance":"twoToThreeDayBatches","weeklyBudgetUSD":90,
    "stores":["Publix"],"trainingDaysPerWeek":4,
    "places":[{"name":"FIU Modesto Maidique Campus","address":null,"usualRestaurants":[]}],
    "days":[
      {"day":"mon","wake":"08:00","leaveHome":"10:15","backHome":"18:00","bed":"00:00",
       "training":{"start":"18:30","durationMinutes":75,"kind":"gym - upper"},
       "events":[{"kind":"classOrWork","title":"Class","start":"11:00","end":"12:15","place":"FIU Modesto Maidique Campus"},
                 {"kind":"mealOut","title":"Lunch with friends","start":"13:00","place":"FIU Modesto Maidique Campus",
                  "with":"friends","restaurants":["Panera Bread","Chipotle"]}]},
      {"day":"Wednesday","wake":"8:00","events":[{"kind":"mealOut","title":"Lunch","start":"1:00 pm",
        "place":"Starbucks Reserve","restaurants":["Starbucks"]}]},
      {"day":"funday","wake":"09:00"}],
    "notes":"Gets bored of chicken fast."},
    "followUps":["What time do you train on Tuesday?","","Do you eat breakfast at home?"]}
    """

    func testParsesRoutineWithMealsOutAtAPlace() throws {
        let extraction = try FuelSetupExtractor.parse(nicolaJSON)
        let draft = extraction.draft
        XCTAssertEqual(draft.weightKg, 78.5, "Numeric strings decode")
        XCTAssertEqual(draft.goal, .cut)
        XCTAssertEqual(draft.restrictions, [.lactoseFree], "Unknown restrictions dropped")
        XCTAssertEqual(draft.dislikedFoods, ["mushrooms"], "De-duplicated, case-insensitive")
        XCTAssertEqual(draft.leftoverTolerance, .twoToThreeDayBatches)
        XCTAssertEqual(extraction.followUps.count, 2, "Empty questions dropped")

        let monday = draft.routine[1]
        XCTAssertEqual(monday.wakeMinutes, 480)
        XCTAssertEqual(monday.bedMinutes, 0)
        XCTAssertEqual(monday.training?.durationMinutes, 75)
        XCTAssertEqual(monday.events.map(\.kind), [.classOrWork, .mealOut], "Sorted by time")
        let lunch = try XCTUnwrap(monday.events.last)
        XCTAssertEqual(lunch.startMinutes, 780)
        XCTAssertEqual(lunch.with, "friends")
        XCTAssertEqual(lunch.restaurants, ["Panera Bread", "Chipotle"])

        let campus = try XCTUnwrap(draft.routine.place(id: lunch.placeID))
        XCTAssertEqual(campus.name, "FIU Modesto Maidique Campus")
        XCTAssertEqual(campus.usualRestaurants, ["Panera Bread", "Chipotle"], "Restaurants eaten there join the place's list")
        XCTAssertEqual(monday.events.first?.placeID, campus.id)

        let wednesday = draft.routine[3]
        XCTAssertEqual(wednesday.events.first?.startMinutes, 780, "\"Wednesday\" and \"1:00 pm\" understood")
        XCTAssertNotNil(draft.routine.place(id: wednesday.events.first?.placeID), "An unknown place is created")
        XCTAssertEqual(draft.routine.days.filter { !$0.isEmpty }.count, 2, "\"funday\" ignored")
    }

    /// Real Sonnet output for a spoken week (FIU classes, Panera with friends, gym, football).
    func testParsesRealModelOutputForASpokenWeek() throws {
        let extraction = try XCTUnwrap(FuelSetupExtractor.parse(Self.spokenWeekResponse))
        let draft = extraction.draft
        XCTAssertEqual(draft.weightKg ?? 0, 78, accuracy: 0.1)
        XCTAssertTrue(draft.restrictions.contains(.lactoseFree))
        XCTAssertEqual(draft.routine.places.count, 1)
        let fiu = try XCTUnwrap(draft.routine.places.first)
        XCTAssertEqual(fiu.usualRestaurants.first, "Panera Bread")
        let monday = draft.routine[1]
        let lunch = try XCTUnwrap(monday.events.first { $0.kind == .mealOut })
        XCTAssertEqual(lunch.startMinutes, 780)
        XCTAssertEqual(lunch.placeID, fiu.id)
        XCTAssertEqual(monday.training?.startMinutes, 1080)
        XCTAssertEqual(monday.training?.durationMinutes, 75)
        XCTAssertNotNil(draft.routine[6].training, "Football with no duration still counts")
        XCTAssertEqual(draft.routine.trainingDaysPerWeek, 5)
        XCTAssertFalse(extraction.followUps.isEmpty)
        XCTAssertLessThanOrEqual(extraction.followUps.count, 5)
    }

    private static let spokenWeekResponse = #"""
{
  "profile": {
    "weightKg": 78.0,
    "heightCm": 182.9,
    "age": 24,
    "sex": null,
    "bodyFatPercent": null,
    "goal": "cut",
    "goalWeightKg": 74.8,
    "weeklyRateKg": null,
    "restrictions": ["lactoseFree"],
    "allergies": [],
    "dislikedFoods": ["mushrooms"],
    "favoriteFoods": ["pasta", "rice bowls"],
    "mealsPerDay": 4,
    "breakfastSkipped": null,
    "eatingWindowStart": null,
    "eatingWindowEnd": null,
    "cookingSkill": null,
    "cookMinutesWeekday": 20,
    "cookMinutesWeekend": null,
    "cookableDaysPerWeek": null,
    "leftoverTolerance": "twoToThreeDayBatches",
    "weeklyBudgetUSD": 100,
    "stores": ["Publix", "Trader Joe's"],
    "trainingDaysPerWeek": 5,
    "places": [
      {
        "name": "FIU Modesto Maidique Campus",
        "address": null,
        "usualRestaurants": ["Panera Bread", "Chipotle"]
      }
    ],
    "days": [
      {
        "day": "mon",
        "wake": "08:00",
        "leaveHome": "10:15",
        "backHome": null,
        "bed": "00:00",
        "training": { "start": "18:00", "durationMinutes": 75, "kind": "gym" },
        "events": [
          {
            "kind": "classOrWork",
            "title": "Class",
            "start": "11:00",
            "end": "12:15",
            "place": null,
            "with": null,
            "restaurants": []
          },
          {
            "kind": "mealOut",
            "title": "Lunch",
            "start": "13:00",
            "end": null,
            "place": "FIU Modesto Maidique Campus",
            "with": "friends",
            "restaurants": ["Panera Bread", "Chipotle"]
          }
        ]
      },
      {
        "day": "tue",
        "wake": "07:15",
        "leaveHome": null,
        "backHome": null,
        "bed": "00:00",
        "training": { "start": "18:00", "durationMinutes": 75, "kind": "gym" },
        "events": [
          {
            "kind": "classOrWork",
            "title": "Class",
            "start": "09:30",
            "end": "10:45",
            "place": null,
            "with": null,
            "restaurants": []
          },
          {
            "kind": "classOrWork",
            "title": "Lab",
            "start": "10:45",
            "end": "14:00",
            "place": null,
            "with": null,
            "restaurants": []
          }
        ]
      },
      {
        "day": "wed",
        "wake": "08:00",
        "leaveHome": "10:15",
        "backHome": null,
        "bed": "00:00",
        "training": null,
        "events": [
          {
            "kind": "classOrWork",
            "title": "Class",
            "start": "11:00",
            "end": "12:15",
            "place": null,
            "with": null,
            "restaurants": []
          },
          {
            "kind": "mealOut",
            "title": "Lunch",
            "start": "13:00",
            "end": null,
            "place": "FIU Modesto Maidique Campus",
            "with": "friends",
            "restaurants": ["Panera Bread", "Chipotle"]
          }
        ]
      },
      {
        "day": "thu",
        "wake": "07:15",
        "leaveHome": null,
        "backHome": null,
        "bed": "00:00",
        "training": { "start": "18:00", "durationMinutes": 75, "kind": "gym" },
        "events": [
          {
            "kind": "classOrWork",
            "title": "Class",
            "start": "09:30",
            "end": "10:45",
            "place": null,
            "with": null,
            "restaurants": []
          },
          {
            "kind": "classOrWork",
            "title": "Lab",
            "start": "10:45",
            "end": "14:00",
            "place": null,
            "with": null,
            "restaurants": []
          }
        ]
      },
      {
        "day": "fri",
        "wake": null,
        "leaveHome": null,
        "backHome": null,
        "bed": "00:00",
        "training": { "start": "18:00", "durationMinutes": 75, "kind": "gym" },
        "events": []
      },
      {
        "day": "sat",
        "wake": "10:00",
        "leaveHome": null,
        "backHome": null,
        "bed": "00:00",
        "training": {
          "start": "10:00",
          "durationMinutes": null,
          "kind": "football"
        },
        "events": []
      },
      {
        "day": "sun",
        "wake": "10:00",
        "leaveHome": null,
        "backHome": null,
        "bed": "00:00",
        "training": null,
        "events": []
      }
    ],
    "notes": "Cutting from 172 lb (78 kg) toward 165 lb (74.8 kg) while trying to keep muscle; sex not stated so calorie/protein targets can't be fully personalized yet. Wakes ~08:00 Mon/Wed, ~07:15 Tue/Thu (earlier class+lab), ~10:00 on weekends — note Saturday football is also listed at 10:00, so actual Saturday wake time may be earlier than the general weekend answer. Lactose intolerant, dislikes mushrooms, loves pasta and rice bowls. Meal preps every Sunday for a few days (fits 2-3 day batch leftovers), can cook ~20 min on weekdays. Grocery budget ~$100/week at Publix and Trader Joe's. Eats 4 meals/day. Bedtime ~midnight most nights."
  },
  "followUps": [
    "What's your sex? It helps set accurate calorie and protein targets.",
    "Do you have a target timeframe or preferred weekly rate for going from 172 to 165 lbs?",
    "How long does your Saturday football session usually run?",
    "What time do you usually wake up on Fridays?"
  ]
}
"""#

    func testGarbageIsUnreadable() {
        XCTAssertThrowsError(try FuelSetupExtractor.parse("Sorry, I can't help with that."))
    }

    func testCurrentDraftRoundTripsThroughThePrompt() throws {
        let draft = try FuelSetupExtractor.parse(nicolaJSON).draft
        let message = FuelSetupExtractor.userMessage(said: "I also train Tuesday at 7am", current: draft)
        XCTAssertTrue(message.hasSuffix("NEW:\nI also train Tuesday at 7am"))
        let currentJSON = try XCTUnwrap(message.components(separatedBy: "CURRENT:\n").last?.components(separatedBy: "\n\nNEW:").first)
        let reparsed = try FuelSetupExtractor.parse("{\"profile\":\(currentJSON)}").draft
        XCTAssertEqual(reparsed.weightKg, draft.weightKg)
        XCTAssertEqual(reparsed.routine[1].events.count, 2)
        XCTAssertEqual(reparsed.routine.places.first?.usualRestaurants, ["Panera Bread", "Chipotle"])
    }

    func testAdoptingAnUpdateKeepsCoordinatesAndDaysLeftOut() throws {
        var known = try FuelSetupExtractor.parse(nicolaJSON).draft
        known.routine.places[0].latitude = 25.756
        known.routine.places[0].longitude = -80.374

        let answer = try FuelSetupExtractor.parse("""
        {"profile":{"weightKg":78.5,"days":[{"day":"tue","training":{"start":"07:00","durationMinutes":60,"kind":"run"}}],
        "places":[{"name":"fiu modesto maidique campus","usualRestaurants":["Panera Bread","Chipotle"]}]},"followUps":[]}
        """)
        let adopted = known.adopting(answer.draft, returnedDays: answer.returnedDays)

        XCTAssertEqual(answer.returnedDays, [2])
        XCTAssertEqual(adopted.weightKg, 78.5)
        XCTAssertEqual(adopted.routine[2].training?.startMinutes, 420)
        XCTAssertEqual(adopted.routine[1].events.count, 2, "Monday wasn't returned, so it's kept")
        XCTAssertEqual(adopted.routine.places.filter { $0.name.lowercased().hasPrefix("fiu") }.count, 1, "Same place by name")
        XCTAssertEqual(adopted.routine.places[0].latitude, 25.756, "Coordinates kept")
        XCTAssertEqual(adopted.routine.place(id: adopted.routine[1].events.last?.placeID)?.latitude, 25.756, "Kept day still points at the place")
        XCTAssertNotNil(adopted.routine.place(id: adopted.routine[3].events.first?.placeID), "A place a kept day uses isn't dropped")
    }

    func testSpokenRemovalsStick() throws {
        var known = try FuelSetupExtractor.parse(nicolaJSON).draft
        known.restrictions = [.glutenFree, .lactoseFree]

        // "I can eat gluten again, and I'm not eating out on Monday any more."
        let answer = try FuelSetupExtractor.parse("""
        {"profile":{"weightKg":78.5,"restrictions":["lactoseFree"],
        "days":[{"day":"mon","wake":"07:00","events":[]}]},"followUps":[]}
        """)
        let adopted = known.adopting(answer.draft, returnedDays: answer.returnedDays)

        XCTAssertEqual(adopted.restrictions, [.lactoseFree], "Gluten-free cleared")
        XCTAssertTrue(adopted.routine[1].events.isEmpty, "Monday's meal out cancelled")
        XCTAssertEqual(adopted.routine[1].wakeMinutes, 420)
        XCTAssertFalse(adopted.routine[3].events.isEmpty, "Wednesday untouched")
    }

    func testMissingFieldsDriveFollowUps() {
        var draft = FuelSetupDraft()
        XCTAssertEqual(draft.missingFields, FuelSetupDraft.Field.allCases)
        draft.weightKg = 80
        draft.heightCm = 180
        draft.age = 30
        draft.sex = .female
        draft.goal = .maintain
        draft.routine[1].wakeMinutes = 420
        draft.mealsPerDay = 3
        XCTAssertTrue(draft.isComplete)
    }

    func testFriendlyErrorForNonPro() {
        XCTAssertTrue(FuelSetupExtractor.message(for: APIError.subscriptionRequired).contains("Pro"))
    }
}

// MARK: - FuelSetupPersistenceTests

@MainActor
final class FuelSetupPersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
        context.insert(UserSettings())
        try context.save()
    }

    func testSaveWritesEveryStoreAndLoadsBack() throws {
        var draft = try FuelSetupExtractor.parse("""
        {"profile":{"weightKg":78,"heightCm":183,"age":24,"sex":"male","goal":"cut","goalWeightKg":75,
        "weeklyRateKg":0.4,"restrictions":["lactoseFree"],"mealsPerDay":4,"breakfastSkipped":false,
        "eatingWindowStart":"08:00","eatingWindowEnd":"21:30","cookMinutesWeekday":20,"cookableDaysPerWeek":5,
        "weeklyBudgetUSD":90,"stores":["Publix"],
        "days":[{"day":"mon","wake":"08:00","bed":"00:00"},{"day":"tue","wake":"08:00"},{"day":"sat","wake":"10:00"}]},
        "followUps":[]}
        """).draft
        draft.notes = "Bored of chicken."

        var observed = 0
        let token = NotificationCenter.default.addObserver(forName: .tempoDietaryProfileChanged, object: nil, queue: nil) { _ in
            observed += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }
        draft.save(to: context)

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<DietaryProfile>()).first)
        XCTAssertEqual(profile.currentWeightKg, 78)
        XCTAssertEqual(profile.primaryGoal, .cut)
        XCTAssertTrue(profile.isLactoseFree)
        XCTAssertFalse(profile.isVegan)

        let daily = try XCTUnwrap(UserDailyPlanProfile.current(in: context))
        XCTAssertEqual(daily.wakeTimeMinutes, 480, "Typical weekday wake")
        XCTAssertEqual(daily.eatingWindowStartMinutes, 480)
        XCTAssertEqual(daily.eatingWindowEndMinutes, 1290)
        XCTAssertEqual(daily.weeklyRoutine?[6].wakeMinutes, 600)

        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(settings.wakeTimeMinutes, 480, "Same wake time everywhere")
        XCTAssertEqual(settings.mealsPerDayPreference, 4)
        XCTAssertEqual(settings.mealIntakeFirstMealHour, 8)
        XCTAssertEqual(settings.mealIntakeLastMealHour, 21)
        XCTAssertEqual(settings.groceryPreferredStores, ["Publix"])
        XCTAssertEqual(observed, 1, "The meal plan is told to follow")

        let loaded = FuelSetupDraft.load(from: context)
        XCTAssertEqual(loaded.weightKg, 78)
        XCTAssertEqual(loaded.restrictions, [.lactoseFree])
        XCTAssertEqual(loaded.routine, draft.routine)
        XCTAssertEqual(loaded.notes, "Bored of chicken.")
        XCTAssertEqual(loaded.mealsPerDay, 4)
    }

    func testFirstLoadSeedsTheWeekFromOnboardingWakeTime() throws {
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        settings.wakeTimeMinutes = 390
        let draft = FuelSetupDraft.load(from: context)
        XCTAssertEqual(draft.routine[1].wakeMinutes, 390)
        XCTAssertEqual(draft.routine[7].wakeMinutes, 390)
    }
}
