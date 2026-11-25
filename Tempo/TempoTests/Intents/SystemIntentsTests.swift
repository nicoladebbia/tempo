//
// SystemIntentsTests.swift
// Tempo
//
// Siri, Shortcuts and the widget button run the same code the app does. These
// pin it through injected stores: "Log water" saves through `WaterStore` (so
// Health and the Today number follow) and tells the widgets, the glasses a
// widget queued reach the store, "Start workout / focus" leave a request for
// the app, "What's next" reads today's real state, and `tempo://` links parse.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SystemIntentsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var healthKit: MockHealthKitService!
    private var defaults: UserDefaults!
    private var appState: AppState!
    private let suiteName = "SystemIntentsTests"

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
        healthKit = MockHealthKitService()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
        appState = AppState(authService: AuthService())
        TempoIntentEnvironment.override = TempoIntentEnvironment(
            context: context, healthKit: healthKit, appState: appState, widgetDefaults: defaults
        )
    }

    override func tearDown() async throws {
        TempoIntentEnvironment.override = nil
        UserDefaults().removePersistentDomain(forName: suiteName)
        container = nil
        context = nil
        healthKit = nil
        defaults = nil
        appState = nil
        try await super.tearDown()
    }

    // MARK: - Log water

    func testLogWaterSavesThroughTheAppsStoreAndPatchesTheWidgets() async throws {
        let outcome = try await WaterLogging.log(ml: 250)
        XCTAssertEqual(outcome.addedMl, 250)
        XCTAssertEqual(outcome.totalMl, 250)
        XCTAssertEqual(WaterStore.total(on: Date(), in: context), 250)

        let second = try await WaterLogging.log(ml: 500)
        XCTAssertEqual(second.totalMl, 750)
        XCTAssertEqual(WaterStore.total(on: Date(), in: context), 750)

        let snapshot = try XCTUnwrap(WidgetSnapshot.read(from: defaults))
        XCTAssertEqual(snapshot.waterMl, 750, "the widgets must show what the app now holds")
    }

    func testLogWaterWritesAHealthSample() async throws {
        _ = try await WaterLogging.log(ml: 330)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(healthKit.writtenWater.map(\.ml), [330])
    }

    func testLogWaterIntentPerformSavesTheAmount() async throws {
        _ = try await LogWaterIntent(amountMl: 400).perform()
        XCTAssertEqual(WaterStore.total(on: Date(), in: context), 400)
    }

    func testLogWaterRejectsAnAmountTheStoreRefuses() async {
        do {
            _ = try await WaterLogging.log(ml: 0)
            XCTFail("0 ml must not be saved")
        } catch {
            XCTAssertEqual(error as? WaterIntentError, .couldNotSave)
        }
        XCTAssertEqual(WaterStore.total(on: Date(), in: context), 0)
    }

    func testOutcomeSentenceNamesTheTotalAndTarget() {
        XCTAssertEqual(
            WaterLogOutcome(addedMl: 250, totalMl: 1250, targetMl: 2900).sentence,
            "250 ml added. \(1250.formatted()) of \(2900.formatted()) ml today."
        )
        XCTAssertEqual(
            WaterLogOutcome(addedMl: 250, totalMl: 250, targetMl: nil).sentence,
            "250 ml added. 250 ml today."
        )
    }

    // MARK: - Glasses queued by the widget

    func testQueuedGlassesReachTheStoreOnceAndAreRemoved() throws {
        XCTAssertTrue(PendingWaterQueue.append(ml: 250, at: Date().addingTimeInterval(-60), defaults: defaults))
        XCTAssertTrue(PendingWaterQueue.append(ml: 250, at: Date(), defaults: defaults))
        let store = WaterStore(context: context, healthKit: healthKit)

        XCTAssertEqual(WaterLogging.drainPending(store: store, context: context, defaults: defaults), 2)
        XCTAssertEqual(WaterStore.total(on: Date(), in: context), 500)
        XCTAssertTrue(PendingWaterQueue.pending(defaults: defaults).isEmpty)
        XCTAssertEqual(try XCTUnwrap(WidgetSnapshot.read(from: defaults)).waterMl, 500)

        // A second drain finds nothing: no glass is ever counted twice.
        XCTAssertEqual(WaterLogging.drainPending(store: store, context: context, defaults: defaults), 0)
        XCTAssertEqual(WaterStore.total(on: Date(), in: context), 500)
    }

    func testQueueKeepsOldestFirst() {
        let early = Date().addingTimeInterval(-120)
        PendingWaterQueue.append(ml: 300, at: Date(), defaults: defaults)
        PendingWaterQueue.append(ml: 100, at: early, defaults: defaults)
        XCTAssertEqual(PendingWaterQueue.pending(defaults: defaults).map(\.ml), [100, 300])
    }

    // MARK: - Start workout / focus

    func testStartWorkoutLeavesARequestForTheApp() async throws {
        _ = try await StartWorkoutIntent().perform()
        XCTAssertEqual(appState.requestedStart, .workout)
    }

    func testStartFocusCarriesTheMinutes() async throws {
        _ = try await StartFocusIntent(minutes: 40).perform()
        XCTAssertEqual(appState.requestedStart, .focus(minutes: 40))
    }

    // MARK: - Deep links

    func testLinksOpenTheTabsTheWidgetsPointAt() throws {
        for tab in AppTab.allCases {
            let url = try XCTUnwrap(URL(string: "tempo://open/\(tab.rawValue)"))
            XCTAssertEqual(TempoDeepLink(url: url), .open(tab))
        }
        for destination in WidgetDestination.allCases {
            XCTAssertNotNil(TempoDeepLink(url: destination.url), "\(destination) must open something")
        }
    }

    func testStartLinks() throws {
        XCTAssertEqual(try TempoDeepLink(url: XCTUnwrap(URL(string: "tempo://start/workout"))), .start(.workout))
        XCTAssertEqual(
            try TempoDeepLink(url: XCTUnwrap(URL(string: "tempo://start/focus"))), .start(.focus(minutes: nil))
        )
        XCTAssertEqual(
            try TempoDeepLink(url: XCTUnwrap(URL(string: "tempo://start/focus?minutes=45"))), .start(.focus(minutes: 45))
        )
        XCTAssertEqual(
            try TempoDeepLink(url: XCTUnwrap(URL(string: "tempo://start/focus?minutes=9999"))), .start(.focus(minutes: 180))
        )
    }

    func testOtherLinksAreLeftAlone() throws {
        for text in ["https://tempo.app/open/today", "tempo://whoop/callback?code=1", "tempo://open/nowhere", "tempo://open"] {
            XCTAssertNil(try TempoDeepLink(url: XCTUnwrap(URL(string: text))), text)
        }
    }

    func testApplyingALinkRoutesTheApp() {
        TempoDeepLink.open(.fuel).apply(to: appState)
        XCTAssertEqual(appState.activeTab, .fuel)
        TempoDeepLink.start(.workout).apply(to: appState)
        XCTAssertEqual(appState.requestedStart, .workout)
    }

    // MARK: - What's next

    func testSpokenAnswerPutsTheSessionMealAndTaskInOrder() {
        let summary = NextUpSummary(
            session: .init(name: "Push", inProgress: false),
            meal: .init(name: "Lunch", time: "13:00"),
            tasksLeft: 2, tasksTotal: 3, firstTask: "Read"
        )
        XCTAssertEqual(
            summary.spoken,
            "Next session: Push. Next meal: Lunch at 13:00. 2 tasks left, starting with Read."
        )
    }

    func testSpokenAnswerForASessionUnderWay() {
        let summary = NextUpSummary(
            session: .init(name: "Pull", inProgress: true), meal: nil, tasksLeft: 1, tasksTotal: 1, firstTask: nil
        )
        XCTAssertEqual(summary.spoken, "Pull is in progress. 1 task left.")
    }

    func testSpokenAnswerWhenEverythingIsDone() {
        let summary = NextUpSummary(session: nil, meal: nil, tasksLeft: 0, tasksTotal: 3, firstTask: nil)
        XCTAssertEqual(summary.spoken, "All your tasks are done. Nothing else is due.")
    }

    func testSpokenAnswerWhenNothingIsPlanned() {
        let summary = NextUpSummary(session: nil, meal: nil, tasksLeft: 0, tasksTotal: 0, firstTask: nil)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.spoken, "Nothing is planned yet today. Open Tempo to set up your day.")
    }

    func testReaderCountsTodaysTasksAndNamesTheFirstOneLeft() throws {
        let read = NonNegotiable(name: "Read", type: .custom, targetValue: 1)
        let stretch = NonNegotiable(name: "Stretch", type: .custom, targetValue: 1)
        let today = DailyAccountability(date: Date())
        context.insert(read)
        context.insert(stretch)
        context.insert(today)
        let done = NonNegotiableProgress(
            date: Date(), currentValue: 1, targetValue: 1, isCompleted: true,
            nonNegotiable: read, dailyAccountability: today
        )
        let open = NonNegotiableProgress(
            date: Date(), targetValue: 1, nonNegotiable: stretch, dailyAccountability: today
        )
        context.insert(done)
        context.insert(open)
        try context.save()

        let summary = NextUpReader.read(in: context)
        XCTAssertEqual(summary.tasksTotal, 2)
        XCTAssertEqual(summary.tasksLeft, 1)
        XCTAssertEqual(summary.firstTask, "Stretch")
    }

    func testReaderOnAnEmptyStoreIsEmpty() {
        XCTAssertTrue(NextUpReader.read(in: context).isEmpty)
    }
}
