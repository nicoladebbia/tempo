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
// Loading, refreshing and saving live in `TodayViewModel`; this file lays the
// page out and presents its sheets.
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

    /// Owns the load, the refreshes and the saved copy. Its first load runs
    /// outside this view's tasks, so leaving the tab cannot cancel it.
    @State
    private var model = TodayViewModel()
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
    private var showMilestoneCelebration = false
    @State
    private var showProgressReport = false
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

    private var viewModel: DashboardViewModel? {
        model.dashboard
    }

    private var liveSnapshot: TodaySnapshot? {
        guard let viewModel, model.isLive else {
            return nil
        }
        return TodaySnapshot.live(
            vm: viewModel,
            firstName: profiles.first?.displayName,
            owned: model.owned,
            whoopConnected: services.whoop.connectionState == .connected,
            healthAuthorized: healthKitAuthorized
        )
    }

    private var phase: TodayPhase {
        TodayPhase.resolve(
            live: liveSnapshot,
            cached: model.cached,
            day: Calendar.current.startOfDay(for: Date())
        )
    }

    private var shownScore: Int? {
        if case let .content(snapshot, _) = phase {
            return snapshot.score
        }
        return nil
    }

    /// Something of Today's own is presented over the page, or a detail
    /// page is pushed on top of it.
    private var isCovered: Bool {
        showMealLogging || showWhoopConnect || showSettings || showInsightDetail || showNonNegotiableSetup
            || showScoreBreakdown || showMilestoneCelebration || showProgressReport || focusModel != nil
            || openMeal != nil || !services.appState.todayPath.isEmpty
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
                }
            }
            .tideCovered(isCovered)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    DashboardSettingsView()
                }
                .persistenceAlert()
            }
            .navigationDestination(for: TodayRoute.self) { route in
                destination(route)
                    .navigationTransition(.zoom(sourceID: route, in: zoom))
            }
        }
        .sensoryFeedback(.selection, trigger: pushes)
        // The shell colours itself from the day score on screen.
        .onChange(of: shownScore, initial: true) { _, score in
            services.appState.dayScore = score
        }
        // Keep the saved copy current so the next launch opens on it.
        .onChange(of: liveSnapshot) { _, snapshot in
            if let snapshot {
                model.liveSnapshotChanged(snapshot)
            }
        }
        .onAppear {
            model.start(services: services, modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoSessionEnded)) { _ in
            model.sessionEnded()
        }
        .onChange(of: model.milestone) { _, milestone in
            if milestone != nil {
                showMilestoneCelebration = true
            }
        }
        .fullScreenCover(isPresented: $showMilestoneCelebration) {
            if let milestone = model.milestone {
                MilestoneCelebrationView(
                    milestone: milestone,
                    onDismiss: { showMilestoneCelebration = false },
                    onShowProgress: milestone == .day30 ? {
                        showMilestoneCelebration = false
                        Task {
                            try? await Task.sleep(for: Tide.sheetHandoff)
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
                model.rereadOwnedState()
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
        .modifier(TodayObservers(model: model))
        .onChange(of: services.appState.activeTab) { _, tab in
            // Coming back to Today: another tab may have settled the day
            // (Training's coach can change today's session). Re-read what
            // those tabs own so Today says the same thing they do.
            if tab == .today {
                model.rereadOwnedState()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Foreground is a sensible moment to re-sync the page and the watch.
            if newPhase == .active {
                Task { await model.syncAll() }
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
                    weather: viewModel?.weather.map { ($0.conditionSymbol, $0.formattedTemperature) },
                    openSettings: { showSettings = true }
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
        // The system's own fade where content passes under the status bar and
        // the glass tab bar, so text behind the bar never fights its labels.
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable {
            // Pull-to-refresh is the user asking for fresh data: skip the
            // in-memory Whoop response cache.
            await services.whoop.invalidateCache()
            await model.syncAll()
        }
        .task(id: scenePhase) {
            // Auto-sync while Today is on screen and the app is in front.
            // Restarted on every scene change; coming to the front already
            // syncs once through the scenePhase observer.
            guard scenePhase == .active else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: DashboardViewModel.autoRefreshInterval)
                guard !Task.isCancelled else {
                    return
                }
                await model.syncAll()
            }
        }
        .accessibilityIdentifier("today.page")
    }

    /// A saved weigh-in or a progress photo exists: Body progress has something to show.
    private var hasStoredBodyData: Bool {
        var descriptor = FetchDescriptor<BodyComposition>()
        descriptor.fetchLimit = 1
        let hasRow = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
        return hasRow || !ProgressPhotoStore().photos().isEmpty
    }

    private var actions: TodayActions {
        TodayActions(
            open: { route in
                var route = route
                // The Body detail only knows the live Whoop/Health feed. When
                // tonight's sleep came from the saved recovery row instead,
                // open the Recovery page, which shows that same row. A person
                // with saved weigh-ins or progress photos still gets Body (and
                // Body progress inside it).
                if route == .body, let body = viewModel?.body, !body.isConnected, body.sleepHours == nil,
                   !hasStoredBodyData
                {
                    route = .recovery
                }
                // A second tap on the same card must not open the page twice.
                if services.appState.pushOnToday(route) {
                    pushes += 1
                }
            },
            openTab: { services.appState.activeTab = $0 },
            openScore: {
                if viewModel != nil {
                    showScoreBreakdown = true
                }
            },
            startWorkout: {
                Task {
                    // The app's one session: a second tap while it is starting
                    // or already up does nothing.
                    let result = await services.workoutSession.start(modelContext: modelContext)
                    if result == .notStartable {
                        // Nothing startable (plan changed under us): the Train
                        // tab shows why and what to do instead.
                        services.appState.activeTab = .train
                    }
                }
            },
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
            SignInPromptCard(style: .tide, onDismiss: { signInNudgeDismissedAt = Date().timeIntervalSince1970 })
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

}

// MARK: - TodayObservers

/// The app events that change what Today shows.
private struct TodayObservers: ViewModifier {
    let model: TodayViewModel

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    private var viewModel: DashboardViewModel? {
        model.dashboard
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: services.whoop.connectionState) { oldState, newState in
                // Refresh when Whoop connects mid-session. Guarded so the
                // launch load (which connects, then refreshes) is not doubled.
                guard model.isLive else {
                    return
                }
                if case .connected = newState, oldState != .connected {
                    Task {
                        await viewModel?.refresh()
                        model.rereadOwnedState()
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
                Task { await model.fuelChanged() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoWorkoutChanged)) { _ in
                // A workout was started, finished or discarded.
                guard model.isLive else {
                    return
                }
                viewModel?.refreshTrainingStatus(modelContext: modelContext)
                viewModel?.pushWatchSnapshot()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoNonNegotiableChanged)) { _ in
                // A task was ticked in Lockdown or on the watch.
                guard model.isLive else {
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
