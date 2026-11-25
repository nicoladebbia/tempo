//
// AppSearchTests.swift
// TempoTests
//
// Local search: matching and ranking, the words people use for settings, and
// that every destination the index can return resolves to a way of opening it.
//

import SwiftData
@testable import Tempo
import XCTest

final class AppSearchTests: XCTestCase {
    private func titles(_ query: String, in entries: [AppSearchEntry] = AppSearchCatalog.all) -> [String] {
        AppSearchMatcher.results(for: query, in: entries).map(\.title)
    }

    // MARK: Matching

    func testAnEmptyQueryFindsNothing() {
        XCTAssertTrue(titles("").isEmpty)
        XCTAssertTrue(titles("   ").isEmpty)
        XCTAssertTrue(titles("?!").isEmpty)
    }

    func testATitleMatchesFromItsFirstLetters() {
        XCTAssertEqual(titles("sche").first, "Schedule")
        XCTAssertEqual(titles("recov").first, "Recovery")
    }

    func testCaseAndAccentsDoNotMatter() {
        XCTAssertEqual(titles("SCHEDULE").first, "Schedule")
        XCTAssertEqual(AppSearchMatcher.normalize("Crème  Brûlée!"), "creme brulee")
    }

    func testAnExactTitleBeatsEverythingElse() {
        XCTAssertEqual(titles("fuel").first, "Fuel")
        XCTAssertEqual(titles("notifications").first, "Notifications")
    }

    func testEveryWordMustMatch() {
        XCTAssertTrue(titles("schedule banana").isEmpty)
        XCTAssertEqual(titles("exercise lib").first, "Exercise library")
    }

    func testNothingMatchesNonsense() {
        XCTAssertTrue(titles("zzzzqx").isEmpty)
    }

    func testResultsAreCapped() {
        let many = (0 ..< 200).map {
            AppSearchEntry(
                id: "x.\($0)", title: "Bench \($0)", subtitle: nil, section: .exercises, icon: "x",
                keywords: [], destination: .exercise(name: "Bench \($0)")
            )
        }
        XCTAssertEqual(AppSearchMatcher.results(for: "bench", in: many).count, AppSearchMatcher.limit)
        XCTAssertEqual(AppSearchMatcher.results(for: "bench", in: many, limit: 5).count, 5)
    }

    func testTiesKeepASensibleOrder() {
        let results = AppSearchMatcher.results(for: "bench", in: [
            entry("b", "Bench Press", .exercises), entry("a", "Bench Press", .screens),
        ])
        XCTAssertEqual(results.map(\.id), ["a", "b"])
    }

    // MARK: Words people use

    func testSettingsAreFoundByTheWordsPeopleUse() {
        let cases: [(query: String, expects: String)] = [
            ("bedtime", "Schedule"),
            ("wake up", "Schedule"),
            ("kg", "Training"),
            ("pounds", "Training"),
            ("whoop", "Connections"),
            ("calendar", "Connections"),
            ("sign out", "Account"),
            ("delete account", "Account"),
            ("upgrade", "Subscription"),
            ("restore purchases", "Subscription"),
            ("quiet hours", "Notifications"),
            ("allergies", "Diet profile"),
            ("pomodoro", "Focus timer"),
            ("download", "Export my data"),
            ("target weight", "Goal"),
            ("checklist", "Get set up"),
        ]
        for item in cases {
            XCTAssertTrue(titles(item.query).contains(item.expects), "\(item.query) should find \(item.expects)")
        }
    }

    func testScreensAreFoundByTheWordsPeopleUse() {
        XCTAssertTrue(titles("sleep").contains("Recovery"))
        XCTAssertTrue(titles("steps").contains("Move"))
        XCTAssertTrue(titles("water").contains("Today's nutrition"))
        XCTAssertTrue(titles("pantry").contains("Kitchen"))
        XCTAssertTrue(titles("shopping list").contains("Groceries"))
        XCTAssertTrue(titles("creatine").contains("Supplements"))
        XCTAssertTrue(titles("injury").contains("Away from the gym"))
        XCTAssertTrue(titles("weekly summary").contains("Week in review"))
        XCTAssertTrue(titles("timeline").contains("Your day"))
        XCTAssertTrue(titles("coach").contains("Ask Tempo"))
    }

    func testFindsAnExerciseByPartsOfItsName() {
        let rows = [
            entry("e1", "Barbell Bench Press", .exercises),
            entry("e2", "Incline Dumbbell Press", .exercises),
            entry("e3", "Squat", .exercises),
        ]
        XCTAssertEqual(titles("ben pre", in: rows), ["Barbell Bench Press"])
        XCTAssertEqual(titles("press", in: rows).count, 2)
    }

    func testAWordInTheNameBeatsAKeywordThatOnlyUsesIt() {
        // "bench" is the equipment of a core move and part of the name of a press.
        let core = AppSearchEntry(
            id: "e1", title: "Decline Crunch", subtitle: nil, section: .exercises, icon: "x",
            keywords: ["core", "bench"], destination: .askTempo
        )
        let press = AppSearchEntry(
            id: "e2", title: "Barbell Bench Press", subtitle: nil, section: .exercises, icon: "x",
            keywords: ["chest", "barbell"], destination: .askTempo
        )
        XCTAssertEqual(titles("bench", in: [core, press]), ["Barbell Bench Press", "Decline Crunch"])
    }

    // MARK: The catalog

    func testEveryEntryHasAUniqueId() {
        let ids = AppSearchCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryEntryHasWordsAndAnIcon() {
        for entry in AppSearchCatalog.all {
            XCTAssertFalse(entry.title.isEmpty, entry.id)
            XCTAssertFalse(entry.icon.isEmpty, entry.id)
        }
    }

    func testEverySettingsPageCanBeFound() {
        let indexed = Set(AppSearchCatalog.settings.compactMap { entry -> SettingsDestination? in
            if case let .settings(page) = entry.destination {
                return page
            }
            return nil
        })
        XCTAssertEqual(indexed, Set(SettingsDestination.allCases))
    }

    func testEveryTrainPageCanBeFound() {
        let indexed = Set(AppSearchCatalog.screens.compactMap { entry -> TrainDestination? in
            if case let .train(page) = entry.destination {
                return page
            }
            return nil
        })
        XCTAssertEqual(indexed, Set(TrainDestination.allCases))
    }

    func testEveryTabAndTodayPageCanBeFound() {
        let destinations = Set(AppSearchCatalog.screens.map(\.destination))
        for tab in AppTab.allCases {
            XCTAssertTrue(destinations.contains(.tab(tab)), "\(tab)")
        }
        for route in TodayRoute.allCases {
            XCTAssertTrue(destinations.contains(.today(route)), "\(route)")
        }
        for section in NutritionSection.allCases where section != .today {
            XCTAssertTrue(
                destinations.contains { destination in
                    if case let .fuel(found, _) = destination {
                        return found == section
                    }
                    return false
                },
                section.rawValue
            )
        }
    }

    func testEveryKitchenSectionCanBeFound() {
        let destinations = Set(AppSearchCatalog.screens.map(\.destination))
        for kitchen in KitchenSection.allCases {
            XCTAssertTrue(destinations.contains(.fuel(.kitchen, kitchen)), kitchen.rawValue)
        }
    }

    // MARK: Destinations resolve

    func testEveryIndexedDestinationResolvesToAnAction() {
        for entry in AppSearchCatalog.all {
            let action = AppSearchAction.resolve(entry.destination)
            switch (entry.destination, action) {
            case let (.tab(tab), .selectTab(selected)): XCTAssertEqual(tab, selected)
            case let (.today(route), .pushToday(pushed)): XCTAssertEqual(route, pushed)
            case (.settingsHome, .presentSettings(nil)): break
            case let (.settings(page), .presentSettings(shown)): XCTAssertEqual(page, shown)
            case let (.train(page), .openTrain(opened, nil)): XCTAssertEqual(page, opened)
            case let (.fuel(section, kitchen), .openFuel(opened, openedKitchen)):
                XCTAssertEqual(section, opened)
                XCTAssertEqual(kitchen, openedKitchen)
            case (.askTempo, .presentAsk): break
            default: XCTFail("\(entry.id) resolved to \(action)")
            }
        }
    }

    func testAnExerciseOpensTheLibraryOnThatExercise() {
        XCTAssertEqual(
            AppSearchAction.resolve(.exercise(name: "Squat")),
            .openTrain(.exerciseLibrary, exercise: "Squat")
        )
    }

    // MARK: The person's own rows

    @MainActor
    func testTheLoaderIndexesExercisesMealsAndPantry() throws {
        let container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(Exercise(name: "Zercher Squat", muscleGroup: .quads, equipment: .barbell, movementPattern: .squat, isCompound: true))
        let preset = MealPreset(name: "Overnight oats", mealType: .breakfast)
        context.insert(preset)
        try context.save()

        let entries = AppSearchLoader.entries(in: context)
        let found = AppSearchMatcher.results(for: "zerc", in: entries)
        XCTAssertEqual(found.first?.destination, .exercise(name: "Zercher Squat"))
        XCTAssertEqual(found.first?.section, .exercises)

        let meal = AppSearchMatcher.results(for: "overnight", in: entries).first
        XCTAssertEqual(meal?.section, .meals)
        XCTAssertEqual(meal.map { AppSearchAction.resolve($0.destination) }, .openFuel(.log, nil))
    }

    // MARK: Helpers

    private func entry(_ id: String, _ title: String, _ section: AppSearchEntry.Section) -> AppSearchEntry {
        AppSearchEntry(
            id: id, title: title, subtitle: nil, section: section, icon: "x", keywords: [], destination: .askTempo
        )
    }
}
