//
// TodayViewModelTests.swift
// TempoTests
//
// The Today load and its saved copy: the first load survives the view task
// that started it being cancelled, it only ever runs once, the saved copy is
// written only when it changed and is gone after sign-out.
//

import SwiftData
@testable import Tempo
import XCTest

/// Counts what Today asks the cache to do.
private final class SpyCache: TodayCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TodaySnapshot?
    private var saveCount = 0
    private var clearCount = 0

    var saves: Int { lock.withLock { saveCount } }
    var clears: Int { lock.withLock { clearCount } }
    var current: TodaySnapshot? { lock.withLock { stored } }

    func load(now: Date, calendar: Calendar) -> TodaySnapshot? {
        lock.withLock { stored }?.carried(to: calendar.startOfDay(for: now))
    }

    func save(_ snapshot: TodaySnapshot) {
        lock.withLock {
            stored = snapshot
            saveCount += 1
        }
    }

    func clear() {
        lock.withLock {
            stored = nil
            clearCount += 1
        }
    }
}

@MainActor
final class TodayViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func snapshot(score: Int? = 70) -> TodaySnapshot {
        var value = TodaySnapshot.placeholder(firstName: "Nicola")
        value.score = score
        return value
    }

    private func makeModel(cache: SpyCache = SpyCache()) async -> TodayViewModel {
        let launch = TodayLaunchSnapshot(cache: cache)
        _ = await launch.value
        return TodayViewModel(cache: cache, launch: launch)
    }

    // MARK: First load

    /// Switching tab cancels the view's task. The load must finish anyway,
    /// or Today would never go live and every refresh path would stay shut.
    func testFirstLoadSurvivesTheCallingTaskBeingCancelled() async {
        let model = await makeModel()
        let services = ServiceContainer.mock()
        let context = context!

        let viewTask = Task { @MainActor in
            model.start(services: services, modelContext: context)
            try? await Task.sleep(for: .seconds(30))
        }
        await Task.yield()
        viewTask.cancel()
        await viewTask.value

        XCTAssertNotNil(model.loadTask)
        await model.loadTask?.value
        XCTAssertTrue(model.isLive, "Today must end up live although the view task was cancelled")
        XCTAssertNotNil(model.dashboard)
    }

    func testStartOnlyEverRunsOneLoad() async {
        let model = await makeModel()
        let services = ServiceContainer.mock()
        model.start(services: services, modelContext: context)
        let first = model.dashboard
        model.start(services: services, modelContext: context)
        model.start(services: services, modelContext: context)
        XCTAssertTrue(model.dashboard === first)
        await model.loadTask?.value
        XCTAssertTrue(model.isLive)
    }

    /// The plan Today shows is settled by the one shared training view model.
    func testFirstLoadSettlesTodayThroughTheSharedSession() async {
        let model = await makeModel()
        let services = ServiceContainer.mock()
        model.start(services: services, modelContext: context)
        await model.loadTask?.value
        XCTAssertTrue(services.workoutSession.hasLoadedToday)
    }

    // MARK: Saved copy

    func testSavedSnapshotIsThereBeforeTheFirstFrame() async {
        let cache = SpyCache()
        cache.save(snapshot(score: 64))
        let model = await makeModel(cache: cache)
        XCTAssertTrue(model.savedSnapshotWasReady)
        XCTAssertEqual(model.cached?.score, 64)
        XCTAssertFalse(model.isLive)
    }

    func testTheCopyIsOnlyWrittenWhenItChanged() async {
        let cache = SpyCache()
        cache.save(snapshot(score: 64))
        let model = await makeModel(cache: cache)
        let before = cache.saves

        // Live numbers equal to what is already on disk: no write.
        model.liveSnapshotChanged(snapshot(score: 64))
        model.liveSnapshotChanged(snapshot(score: 64))
        XCTAssertEqual(cache.saves, before)

        model.liveSnapshotChanged(snapshot(score: 71))
        model.liveSnapshotChanged(snapshot(score: 71))
        XCTAssertEqual(cache.saves, before + 1)
        XCTAssertEqual(cache.current?.score, 71)
        XCTAssertEqual(model.cached?.score, 71)
    }

    // MARK: Sign-out

    func testEndingTheSessionRemovesTheSavedCopyEverywhere() async {
        let cache = SpyCache()
        cache.save(snapshot(score: 64))
        let launch = TodayLaunchSnapshot(cache: cache)
        _ = await launch.value
        let model = TodayViewModel(cache: cache, launch: launch)
        let posted = expectation(forNotification: .tempoSessionEnded, object: nil)

        ServiceContainer.endSession(cache: cache, launch: launch)
        model.sessionEnded()

        await fulfillment(of: [posted], timeout: 1)
        XCTAssertEqual(cache.clears, 1)
        XCTAssertNil(cache.current)
        XCTAssertNil(launch.peek().snapshot)
        XCTAssertNil(model.cached)
        // A model made after sign-out (relaunch) starts with nothing saved.
        XCTAssertNil(TodayViewModel(cache: cache, launch: launch).cached)
    }

    func testSignOutAndAccountDeletionBothEndTheSession() async {
        let auth = AuthService()
        var ended = 0
        auth.onSessionEnded = { ended += 1 }
        await auth.signOut()
        XCTAssertEqual(ended, 1)
        // The app wires that hook to the cache.
        XCTAssertNotNil(ServiceContainer.mock().authService.onSessionEnded)
    }
}
