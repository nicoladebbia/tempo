//
// TodayView.swift
// Tempo
//
// The Today tab: one page that answers "what do I do now".
//
// It draws a `TodaySnapshot`. On launch that is the copy saved on disk from
// the last session, so real content is on screen in the first frame; the live
// numbers replace it quietly once the first refresh has finished. The loading
// placeholder only appears when there is nothing saved (a first-ever launch).
//
// Everything the old Dashboard hosted lives here: the refresh lifecycle, the
// watch and widget pushes, the setup and sign-in prompts, weather, insights,
// the score breakdown and the milestone celebration.
//

import Combine
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.tideMood)
    private var mood

    @Query
    private var profiles: [UserProfile]
    @Query
    private var settings: [UserSettings]
    @Query
    private var nonNegotiables: [NonNegotiable]

    /// Read once per process: the snapshot the last session left behind.
    private static let launchSnapshot = TodayCache.shared.load()

    @State
    private var viewModel: DashboardViewModel?
    @State
    private var cached: TodaySnapshot? = TodayView.launchSnapshot
    @State
    private var owned = TodaySnapshot.Owned()
    @State
    private var hasAppeared = false
    /// A meal / plan / profile event arrived before the first load finished.
    /// Replayed once it has, so the card never keeps a pre-event target.
    @State
    private var fuelRefreshPending = false
    @State
    private var showMealLogging = false
    @State
    private var showWhoopConnect = false
    @State
    private var showSettings = false
    @State
    private var showInsightDetail = false
    @State
    private var showNonNegotiableSetup = false
    @State
    private var showScoreBreakdown = false
    @State
    private var activeMilestone: MilestoneService.Milestone?
    @State
    private var showMilestoneCelebration = false
    @State
    private var showProgressReport = false
    @State
    private var workoutStartRequest = 0
    @State
    private var focusModel: AccountabilityViewModel?
    @State
    private var openMeal: PlannedMeal?
    @State
    private var pushes = 0

    @Namespace
    private var zoom

    @AppStorage("dashboard.signInNudgeDismissedAt")
    private var signInNudgeDismissedAt: Double = 0
    @AppStorage("healthKitAuthorized")
    private var healthKitAuthorized = false
    @AppStorage("hasCompletedSetup")
    private var hasCompletedSetup = false

    // MARK: What to draw

    private var liveSnapshot: TodaySnapshot? {
        guard let viewModel, hasAppeared else {
            return nil
        }
        // A failed sync must not wipe good numbers off the screen.
        if case .error = viewModel.loadState, cached != nil {
            return nil
        }
        return TodaySnapshot.live(
            vm: viewModel,
            firstName: profiles.first?.displayName,
            owned: owned,
            whoopConnected: services.whoop.connectionState == .connected,
            healthAuthorized: healthKitAuthorized
        )
    }

    private var phase: TodayPhase {
        var error: String?
        if case let .error(message) = viewModel?.loadState {
            error = message
        }
        return TodayPhase.resolve(live: liveSnapshot, cached: cached, error: error)
    }

    private var shownScore: Int? {
        if case let .content(snapshot, _) = phase {
            return snapshot.score
        }
        return nil
    }

    var body: some View {
        @Bindable
        var appState = services.appState
        let phase = phase
        return NavigationStack(path: $appState.todayPath) {
            ZStack {
                TideBackground()
                switch phase {
                case let .content(snapshot, isLive):
                    page(snapshot, isLive: isLive)
                        .onAppear {
                            TempoSignpost.todayContentShown(source: isLive ? "fresh" : "saved")
                        }
                case .firstLoad:
                    page(.placeholder(firstName: profiles.first?.displayName), isLive: false)
                        .redacted(reason: .placeholder)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("today.loading")
                case let .failed(message):
                    ErrorStateView(
                        title: "Sync failed.",
                        message: message,
                        retryAction: {
                            Task {
                                await viewModel?.refresh()
                                viewModel?.refreshTrainingStatus(modelContext: modelContext)
                                viewModel?.refreshAccountability(modelContext: modelContext)
                                reloadOwned()
                            }
                        }
                    )
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .tempoSettingsToolbar(isPresented: $showSettings)
            .navigationDestination(for: TodayRoute.self) { route in
                destination(route)
                    .navigationTransition(.zoom(sourceID: route, in: zoom))
            }
        }
        .sensoryFeedback(.selection, trigger: pushes)
        .todayWorkoutFlow(startRequest: workoutStartRequest)
        // The shell colours itself from the day score on screen.
        .onChange(of: shownScore, initial: true) { _, score in
            services.appState.dayScore = score
        }
        // Keep the saved copy current so the next launch opens on it.
        .onChange(of: liveSnapshot) { _, snapshot in
            if let snapshot {
                cached = snapshot
                TodayCache.shared.save(snapshot)
            }
        }
        .task {
            await firstLoad()
        }
        .fullScreenCover(isPresented: $showMilestoneCelebration) {
            if let milestone = activeMilestone {
                MilestoneCelebrationView(
                    milestone: milestone,
                    onDismiss: { showMilestoneCelebration = false },
                    onShowProgress: milestone == .day30 ? {
                        showMilestoneCelebration = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showProgressReport = true
                        }
                    } : nil
                )
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { focusModel != nil },
            set: { if !$0 { focusModel = nil } }
        )) {
            if let focusModel {
                FocusTimerView(viewModel: focusModel)
            }
        }
        .sheet(isPresented: $showProgressReport) {
            ProgressReportView()
        }
        .sheet(isPresented: $showMealLogging) {
            MealLoggingView()
        }
        .sheet(item: $openMeal) { meal in
            NavigationStack {
                MealDetailView(meal: meal)
            }
        }
        .sheet(isPresented: $showWhoopConnect, onDismiss: {
            Task {
                await viewModel?.refresh()
                viewModel?.refreshTrainingStatus(modelContext: modelContext)
                reloadOwned()
            }
        }) {
            NavigationStack {
                WhoopConnectionView()
            }
        }
        .sheet(isPresented: $showNonNegotiableSetup, onDismiss: {
            viewModel?.refreshAccountability(modelContext: modelContext)
            viewModel?.pushWatchSnapshot()
        }) {
            NavigationStack {
                NonNegotiableSetupView()
            }
        }
        .sheet(isPresented: $showScoreBreakdown) {
            if let viewModel {
                ScoreBreakdownSheet(vm: viewModel)
            }
        }
        .sheet(isPresented: $showInsightDetail) {
            if let viewModel {
                InsightDetailSheet(vm: viewModel)
            }
        }
        .modifier(TodayObservers(
            viewModel: viewModel,
            hasAppeared: hasAppeared,
            fuelRefreshPending: $fuelRefreshPending,
            refreshFuel: { await refreshFuelAfterChange() },
            reloadOwned: reloadOwned
        ))
        .onChange(of: scenePhase) { _, newPhase in
            // Foreground is a sensible moment to re-sync the page and the watch.
            guard hasAppeared, newPhase == .active else {
                return
            }
            Task {
                await viewModel?.refresh()
                viewModel?.refreshTrainingStatus(modelContext: modelContext)
                viewModel?.refreshAccountability(modelContext: modelContext)
                viewModel?.pushWatchSnapshot()
                reloadOwned()
            }
        }
    }

    // MARK: - Page

    private func page(_ snapshot: TodaySnapshot, isLive: Bool) -> some View {
        let actions = actions
        return ScrollView {
            VStack(spacing: Tide.s4) {
                TodayHeader(
                    snapshot: snapshot,
                    dateLine: TempoDateFormatters.dashboardHeader.string(from: Date()),
                    weather: viewModel?.weather.map { ($0.conditionSymbol, $0.formattedTemperature) }
                )
                TodayHero(snapshot: snapshot, actions: actions)
                prompts
                TodayNextCard(
                    action: TodayNextAction.choose(
                        for: snapshot,
                        hour: Calendar.current.component(.hour, from: Date())
                    ),
                    snapshot: snapshot,
                    actions: actions
                )
                TodayBodyRow(snapshot: snapshot, actions: actions, namespace: zoom)
                TodayFuelCard(fuel: snapshot.fuel, actions: actions)
                    .matchedTransitionSource(id: TodayRoute.fuel, in: zoom)
                TodayTasksCard(snapshot: snapshot, actions: actions, namespace: zoom)
                TodayMindMoveRow(snapshot: snapshot, actions: actions, namespace: zoom)
                if isLive, let viewModel {
                    notes(viewModel)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
            .animation(Tide.snap, value: snapshot)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            // Pull-to-refresh is the user asking for fresh data: skip the
            // in-memory Whoop response cache.
            await services.whoop.invalidateCache()
            await syncAll()
        }
        .task {
            // Auto-sync while Today is on screen. Cancelled when it goes
            // away; foregrounding already syncs via the scenePhase observer.
            while !Task.isCancelled {
                try? await Task.sleep(for: DashboardViewModel.autoRefreshInterval)
                guard !Task.isCancelled, hasAppeared,
                      UIApplication.shared.applicationState == .active
                else {
                    continue
                }
                await syncAll()
            }
        }
        .accessibilityIdentifier("today.page")
    }

    private var actions: TodayActions {
        TodayActions(
            open: { route in
                pushes += 1
                services.appState.todayPath.append(route)
            },
            openTab: { services.appState.activeTab = $0 },
            openScore: {
                if viewModel != nil {
                    showScoreBreakdown = true
                }
            },
            startWorkout: { workoutStartRequest += 1 },
            openMeal: { meal in
                // The live plan row if it is still there, else the Fuel tab.
                if let planned = viewModel?.fuel.nextMeal, planned.id == meal.id {
                    openMeal = planned
                } else {
                    services.appState.activeTab = .fuel
                }
            },
            logMeal: { showMealLogging = true },
            startFocus: { focusModel = AccountabilityViewModel(engine: services.accountabilityEngine) },
            setUpTasks: { showNonNegotiableSetup = true },
            connectWearable: { showWhoopConnect = true },
            allowHealth: {
                Task {
                    try? await services.healthKit.requestAuthorization()
                    await viewModel?.refresh()
                }
            }
        )
    }

    @ViewBuilder
    private func destination(_ route: TodayRoute) -> some View {
        switch route {
        case .recovery: RecoveryTabView(embedded: true)
        case .lockdown: LockdownTabView(embedded: true)
        case .body: BodyQuadrantDetailView(data: viewModel?.body ?? .empty)
        case .move: MoveQuadrantDetailView(data: viewModel?.move ?? .empty)
        case .mind: MindQuadrantDetailView(data: viewModel?.mind ?? .empty)
        case .fuel:
            if let fuel = viewModel?.fuel {
                FuelQuadrantDetailContainer(fuelData: fuel)
            } else {
                DailyNutritionSummaryView()
            }
        }
    }

    // MARK: - Prompts (sign-in, setup)

    /// Signed-out users get a nudge to sign in. Hidden in ordinary UI tests
    /// (they run signed out) unless a test asks for it, and for 24 h after
    /// "Not now".
    private var showSignInNudge: Bool {
        if case .authenticated = services.authService.authState {
            return false
        }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-skip-onboarding"), !args.contains("--uitesting-signin-nudge") {
            return false
        }
        return Date().timeIntervalSince1970 - signInNudgeDismissedAt > 24 * 60 * 60
    }

    @ViewBuilder
    private var prompts: some View {
        if showSignInNudge {
            SignInPromptCard(onDismiss: { signInNudgeDismissedAt = Date().timeIntervalSince1970 })
                .transition(.opacity)
        }
        if !hasCompletedSetup {
            let whoopDone = services.whoop.connectionState == .connected
            let tasksDone = !nonNegotiables.isEmpty
            let trainingDone = !settings.isEmpty
            if !(whoopDone && tasksDone && trainingDone) {
                TodaySetupCard(
                    steps: [
                        .init(
                            id: "whoop", title: "Connect Whoop",
                            detail: "Recovery, sleep and strain, read for you.",
                            icon: "waveform.path.ecg", done: whoopDone,
                            action: { showWhoopConnect = true }
                        ),
                        .init(
                            id: "training", title: "Set up training",
                            detail: "Choose your split and training days.",
                            icon: "dumbbell.fill", done: trainingDone,
                            action: { showSettings = true }
                        ),
                        .init(
                            id: "tasks", title: "Choose daily tasks",
                            detail: "The few things you do every day.",
                            icon: "checklist", done: tasksDone,
                            action: { showNonNegotiableSetup = true }
                        )
                    ],
                    onSkip: {
                        withAnimation(Tide.snap) { hasCompletedSetup = true }
                    }
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private func notes(_ vm: DashboardViewModel) -> some View {
        let insight = vm.currentInsight
        TodayNoteCard(
            label: "Insight",
            icon: insight.icon,
            text: insight.text,
            pageCount: vm.insights.count,
            onOpen: { showInsightDetail = true },
            onNext: {
                withAnimation(Tide.snap) { vm.nextInsight() }
            }
        )
        .accessibilityIdentifier("today.insight")
        if let advice = vm.weather?.recommendation {
            TodayNoteCard(
                label: "Weather",
                icon: vm.weather?.conditionSymbol ?? "cloud.fill",
                text: advice
            )
            .accessibilityIdentifier("today.weather")
        }
    }

    // MARK: - Loading and refreshing

    /// The first load of the session. Same order as the old Dashboard: the
    /// order matters (Whoop is checked before the first refresh, the gate
    /// opens before the weather fetch).
    private func firstLoad() async {
        guard viewModel == nil else {
            return
        }
        let vm = DashboardViewModel(services: services)
        vm.setFuelContext(modelContext)
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            vm.setUserName(profile.displayName)
        }
        viewModel = vm
        // Validate the Whoop connection BEFORE fetching data, so refresh()
        // never reads connectionState before the tokens are verified.
        await services.whoop.checkConnectionOnLaunch()

        // Take the name from the Whoop profile if ours is still the default.
        if let profile = try? modelContext.fetch(descriptor).first,
           profile.displayName == TodayGreeting.placeholderName,
           let whoopService = services.whoop as? WhoopService,
           let firstName = whoopService.profileFirstName, !firstName.isEmpty
        {
            let fullName = [firstName, whoopService.profileLastName].compactMap(\.self).joined(separator: " ")
            profile.displayName = fullName
            profile.updatedAt = Date()
            try? modelContext.save()
            vm.setUserName(fullName)
        }

        // Same deload rule as Training (start date, Auto Deload, fatigue).
        vm.setDeloadWeek(services.trainingEngine.isDeloadWeek(on: Date(), modelContext: modelContext))
        vm.loadScoreHistory(modelContext: modelContext)

        await vm.refresh()
        vm.refreshTrainingStatus(modelContext: modelContext)
        vm.refreshAccountability(modelContext: modelContext)
        reloadOwned()

        vm.persistDailyScore(modelContext: modelContext)
        vm.loadScoreHistory(modelContext: modelContext)

        // App launch is a sensible moment to sync the watch, so the wrist
        // never shows a placeholder.
        vm.pushWatchSnapshot()

        // Open the gate BEFORE the weather fetch (network, can take many
        // seconds): a plan applied or meal logged during it must refresh
        // the Fuel card, not be dropped.
        withAnimation(Tide.snap) {
            hasAppeared = true
        }
        if fuelRefreshPending {
            fuelRefreshPending = false
            await refreshFuelAfterChange()
        }

        await vm.fetchWeather()

        if let milestone = MilestoneService.checkMilestone(modelContext: modelContext) {
            activeMilestone = milestone
            showMilestoneCelebration = true
        }
    }

    /// Full refresh used by pull-to-refresh and the 5-minute auto-sync.
    private func syncAll() async {
        guard let vm = viewModel else {
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
    private func refreshFuelAfterChange() async {
        guard let vm = viewModel else {
            return
        }
        await vm.refresh(force: true)
        vm.refreshTrainingStatus(modelContext: modelContext)
        vm.refreshAccountability(modelContext: modelContext)
        vm.pushWatchSnapshot()
        reloadOwned()
    }

    /// Re-read the numbers Today takes from the tab that owns them.
    private func reloadOwned() {
        owned = TodaySnapshot.Owned.read(in: modelContext)
    }
}

// MARK: - TodayObservers

/// The app events that change what Today shows.
private struct TodayObservers: ViewModifier {
    let viewModel: DashboardViewModel?
    let hasAppeared: Bool
    @Binding var fuelRefreshPending: Bool
    let refreshFuel: () async -> Void
    let reloadOwned: () -> Void

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    func body(content: Content) -> some View {
        content
            .onChange(of: services.whoop.connectionState) { oldState, newState in
                // Refresh when Whoop connects mid-session. Guarded so the
                // launch load (which connects, then refreshes) is not doubled.
                guard hasAppeared else {
                    return
                }
                if case .connected = newState, oldState != .connected {
                    Task {
                        await viewModel?.refresh()
                        viewModel?.refreshTrainingStatus(modelContext: modelContext)
                        reloadOwned()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoWaterLogged)) { _ in
                viewModel?.reloadHydration()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoMealWillBeRemoved)) { note in
                // Synchronous: the model is deleted right after the post returns.
                if let id = note.userInfo?["id"] as? UUID {
                    viewModel?.dropNextMeal(mealID: id)
                }
            }
            .onReceive(
                Publishers.MergeMany(
                    // A server-built week landing, or a diet-profile edit,
                    // changes today's target without a meal being logged.
                    DashboardViewModel.fuelRefreshTriggers.map { NotificationCenter.default.publisher(for: $0) }
                )
                // Regenerate posts a profile change then the plan; one refresh.
                .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            ) { _ in
                guard hasAppeared else {
                    fuelRefreshPending = true
                    return
                }
                Task { await refreshFuel() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoWorkoutChanged)) { _ in
                // A workout was started, finished or discarded.
                guard hasAppeared else {
                    return
                }
                viewModel?.refreshTrainingStatus(modelContext: modelContext)
                viewModel?.pushWatchSnapshot()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoNonNegotiableChanged)) { _ in
                // A task was ticked in Lockdown or on the watch.
                guard hasAppeared else {
                    return
                }
                viewModel?.refreshAccountability(modelContext: modelContext)
                viewModel?.pushWatchSnapshot()
            }
    }
}

// MARK: - Placeholder

extension TodaySnapshot {
    /// Shape-only content for the first-ever launch, drawn redacted.
    static func placeholder(firstName: String?) -> TodaySnapshot {
        TodaySnapshot(
            day: Calendar.current.startOfDay(for: Date()),
            firstName: firstName,
            score: nil,
            workout: Workout(status: .none, name: nil, inProgress: false, durationMinutes: nil),
            recovery: Recovery(
                score: nil, sleepHours: nil, sleepPerformance: nil, hrv: nil, restingHR: nil, hasSource: true
            ),
            fuel: Fuel(waterMl: 0, waterTargetMl: DailyHydrationTarget.fallbackBaseMl),
            tasks: [],
            study: Study(minutes: 0, targetMinutes: 0, nextExam: nil),
            streakDays: 0,
            steps: nil,
            stepsTarget: 10000,
            moveConnected: true,
            nextMeal: nil
        )
    }
}

#Preview {
    TodayView()
        .environment(ServiceContainer.mock())
}
