//
// TodayViewModel.swift
// Tempo
//
// Loads and refreshes what the Today screen draws. The screen only renders:
// the load order, the saved copy on disk, the writes that go with the first
// load (display name, day score) and the milestone check all live here.
//
// The first load runs in its own task, not the view's: switching tab while it
// is running cannot cancel it, so Today always ends up live.
//

import SwiftData
import SwiftUI

@Observable
@MainActor
final class TodayViewModel {
    /// The numbers behind the page. Nil until `start` has been called.
    private(set) var dashboard: DashboardViewModel?
    /// True once the first load has finished and live numbers may be drawn.
    private(set) var isLive = false
    /// Values read from the tab that owns them (water target, saved recovery row).
    private(set) var owned = TodaySnapshot.Owned()
    /// The last snapshot drawn: from disk at launch, then kept current.
    private(set) var cached: TodaySnapshot?
    /// A milestone to celebrate, found after the first load.
    var milestone: MilestoneService.Milestone?

    /// The first load. Tests await it; nothing else needs to.
    @ObservationIgnored
    private(set) var loadTask: Task<Void, Never>?
    /// Whether the saved snapshot was already in memory for the first frame.
    @ObservationIgnored
    let savedSnapshotWasReady: Bool

    /// How long the first load waits for today's plan (and the daily coach)
    /// before going live without it. The plan is re-read when it lands.
    static let planWait: Duration = .seconds(4)

    @ObservationIgnored
    private let cache: any TodayCaching
    @ObservationIgnored
    private let launch: TodayLaunchSnapshot
    @ObservationIgnored
    private var lastSaved: TodaySnapshot?
    @ObservationIgnored
    private var fuelRefreshPending = false
    @ObservationIgnored
    private var services: ServiceContainer?
    @ObservationIgnored
    private var modelContext: ModelContext?

    init(cache: any TodayCaching = TodayCache.shared, launch: TodayLaunchSnapshot = .shared) {
        self.cache = cache
        self.launch = launch
        let saved = launch.peek()
        savedSnapshotWasReady = saved.ready
        cached = saved.snapshot
        lastSaved = saved.snapshot
    }

    // MARK: - First load

    /// Starts the first load once. Later calls do nothing, so it is safe to
    /// call every time the screen appears.
    func start(services: ServiceContainer, modelContext: ModelContext) {
        guard loadTask == nil else {
            return
        }
        self.services = services
        self.modelContext = modelContext
        let vm = DashboardViewModel(services: services)
        vm.setFuelContext(modelContext)
        if let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first {
            vm.setUserName(profile.displayName)
        }
        dashboard = vm
        // Not a child of the caller: a view task that gets cancelled (tab
        // switch) must not take the load down with it.
        loadTask = Task { [weak self] in
            await self?.load(vm, services: services, modelContext: modelContext)
        }
    }

    /// Same order as the old Dashboard, and the order matters: Whoop is
    /// checked before the first refresh, and the page goes live before the
    /// weather fetch.
    private func load(_ vm: DashboardViewModel, services: ServiceContainer, modelContext: ModelContext) async {
        if !savedSnapshotWasReady, cached == nil, let saved = await launch.value, !isLive {
            cached = saved
            lastSaved = saved
        }

        // Validate the Whoop connection BEFORE fetching data, so refresh()
        // never reads connectionState before the tokens are verified.
        await services.whoop.checkConnectionOnLaunch()
        adoptWhoopName(vm, services: services, modelContext: modelContext)

        // Today's plan is settled by the same view model the Train tab uses
        // (it runs the daily coach, which can change the session and the
        // water target). Start it now so Today's first live numbers already
        // agree with Train and Fuel.
        services.workoutSession.prepare(modelContext: modelContext)
        let dayBefore = daySignature(in: modelContext)

        // Same deload rule as Training (start date, Auto Deload, fatigue).
        vm.setDeloadWeek(services.trainingEngine.isDeloadWeek(on: Date(), modelContext: modelContext))
        vm.loadScoreHistory(modelContext: modelContext)

        await vm.refresh()
        let planReady = await waitForPlan(services.workoutSession)
        if daySignature(in: modelContext) != dayBefore {
            // The coach changed the day while the numbers were loading.
            await vm.refresh(force: true)
        }
        vm.refreshTrainingStatus(modelContext: modelContext)
        vm.refreshAccountability(modelContext: modelContext)
        reloadOwned()

        vm.persistDailyScore(modelContext: modelContext)
        vm.loadScoreHistory(modelContext: modelContext)

        // App launch is a sensible moment to sync the watch, so the wrist
        // never shows a placeholder.
        vm.pushWatchSnapshot()

        // Go live BEFORE the weather fetch (network, can take many seconds):
        // a plan applied or meal logged during it must refresh the Fuel
        // card, not be dropped.
        withAnimation(Tide.snap) {
            isLive = true
        }
        TempoSignpost.todayContentShown(source: "fresh")
        TempoSignpost.mark("TodayLive")
        if fuelRefreshPending {
            fuelRefreshPending = false
            await refreshFuelAfterChange()
        }
        if !planReady {
            // The plan took longer than the wait: settle the page when it lands.
            Task { [weak self] in
                await services.workoutSession.prepare(modelContext: modelContext).value
                await self?.refreshFuelAfterChange()
            }
        }

        await vm.fetchWeather()

        milestone = MilestoneService.checkMilestone(modelContext: modelContext)
    }

    /// Takes the name from the Whoop profile if ours is still the default.
    private func adoptWhoopName(_ vm: DashboardViewModel, services: ServiceContainer, modelContext: ModelContext) {
        guard let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first,
              profile.displayName == TodayGreeting.placeholderName,
              let whoop = services.whoop as? WhoopService,
              let firstName = whoop.profileFirstName, !firstName.isEmpty
        else {
            return
        }
        let fullName = [firstName, whoop.profileLastName].compactMap(\.self).joined(separator: " ")
        profile.displayName = fullName
        profile.updatedAt = Date()
        try? modelContext.save()
        vm.setUserName(fullName)
    }

    /// True if today's plan was settled within `planWait`.
    private func waitForPlan(_ session: WorkoutSessionCoordinator) async -> Bool {
        let deadline = ContinuousClock.now + Self.planWait
        while !session.hasLoadedToday, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(40))
        }
        return session.hasLoadedToday
    }

    /// What kind of day today's plan says it is. Used to notice the coach
    /// changing it under a refresh.
    private func daySignature(in modelContext: ModelContext) -> String {
        guard let plan = DashboardViewModel.todayWorkoutPlan(in: modelContext) else {
            return "none"
        }
        return "\(plan.type.rawValue)-\(plan.status.rawValue)"
    }

    // MARK: - Refreshing

    /// Full refresh: pull-to-refresh and the periodic sync.
    func syncAll() async {
        guard let vm = dashboard, let modelContext, isLive else {
            return
        }
        await vm.refresh()
        vm.refreshTrainingStatus(modelContext: modelContext)
        vm.refreshAccountability(modelContext: modelContext)
        vm.persistDailyScore(modelContext: modelContext)
        vm.loadScoreHistory(modelContext: modelContext)
        vm.pushWatchSnapshot()
        reloadOwned()
    }

    /// A meal was logged or today's target changed: re-pull Fuel, then the
    /// things that depend on it.
    func refreshFuelAfterChange() async {
        guard let vm = dashboard, let modelContext else {
            return
        }
        await vm.refresh(force: true)
        vm.refreshTrainingStatus(modelContext: modelContext)
        vm.refreshAccountability(modelContext: modelContext)
        vm.pushWatchSnapshot()
        reloadOwned()
    }

    /// A meal / plan / profile event arrived. Before the page is live it is
    /// remembered and replayed, so the card never keeps a pre-event target.
    func fuelChanged() async {
        guard isLive else {
            fuelRefreshPending = true
            return
        }
        await refreshFuelAfterChange()
    }

    /// Another tab may have settled the day (the coach can change today's
    /// session and water target): re-read what those tabs own.
    func rereadOwnedState() {
        guard isLive, let modelContext else {
            return
        }
        dashboard?.refreshTrainingStatus(modelContext: modelContext)
        reloadOwned()
    }

    /// Re-read the numbers Today takes from the tab that owns them.
    func reloadOwned() {
        guard let modelContext else {
            return
        }
        owned = TodaySnapshot.Owned.read(in: modelContext)
    }

    // MARK: - Saved copy

    /// The live page changed: keep the saved copy current so the next launch
    /// opens on it. Writes only when something is actually different.
    func liveSnapshotChanged(_ snapshot: TodaySnapshot) {
        cached = snapshot
        // The widgets draw this same snapshot.
        WidgetSyncService.publish(today: snapshot)
        guard snapshot != lastSaved else {
            return
        }
        lastSaved = snapshot
        cache.save(snapshot)
    }

    /// Sign-out or account deletion: drop the copy held in memory. The file
    /// itself is removed by the auth service.
    func sessionEnded() {
        cached = nil
        lastSaved = nil
    }
}
