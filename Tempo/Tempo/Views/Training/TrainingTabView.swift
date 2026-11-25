//
// TrainingTabView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Training Tab Container

// Per BUILD_PLAN step 9.8 — Training tab root.
// Default: TodayWorkoutView. Navigation to: WeekPlanView, ExerciseLibraryView,
// ProgressChartsView, TrainingSettingsView.

struct TrainingTabView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    /// Pause/travel-pain feature — see AwayModeSheet.swift.
    @State
    private var showAwayMode = false
    @State
    private var showSettings = false
    @State
    private var opened = 0
    /// The page open inside Train. Search sets it through `requestedTrain`.
    @State
    private var path: [TrainDestination] = []
    /// The exercise search opened the library on.
    @State
    private var librarySearch = ""

    var body: some View {
        // The session (view model and its screens) is owned by the app, not
        // by this tab: Today and the Move detail drive the same one.
        @Bindable
        var session = services.workoutSession
        let viewModel = session.viewModel
        return NavigationStack(path: $path) {
            TodayWorkoutView(
                viewModel: viewModel,
                showActiveWorkout: $session.showActiveWorkout,
                showSummary: $session.showSummary
            )
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    moreMenu(viewModel: viewModel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        opened += 1
                        showSettings = true
                    } label: {
                        Image(systemName: TempoSymbols.settings)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: TrainDestination.self) { page in
                destination(page, viewModel: viewModel)
            }
            .tideCovered(showAwayMode || showSettings)
            .sheet(isPresented: $showAwayMode) {
                AwayModeSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    DashboardSettingsView()
                }
                .persistenceAlert()
            }
        }
        .sensoryFeedback(.selection, trigger: opened)
        // Search asked for a page here: open it, then clear the request.
        .onChange(of: path) { _, path in
            if path.isEmpty {
                librarySearch = ""
            }
        }
        .onChange(of: services.appState.requestedTrain, initial: true) { _, request in
            guard let request else {
                return
            }
            services.appState.requestedTrain = nil
            open(request)
        }
        .onReceive(
            // Tier 3.3 — re-personalize the training week when the schedule
            // inputs change (football days / split edited in TrainingSettingsDetailView).
            // Debounced 0.6s so a burst of chip toggles regenerates once, matching
            // the Nutrition observer. Skips while a workout is active so an edit
            // can't disturb an in-progress session (the guard also protects this).
            NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged)
                .debounce(for: .seconds(0.6), scheduler: DispatchQueue.main)
        ) { _ in
            guard !viewModel.sessionState.isActive else {
                return
            }
            viewModel.repersonalizeSchedule(modelContext: modelContext)
        }
        .persistenceAlert()
    }

    // MARK: - Pages

    @ViewBuilder
    private func destination(_ page: TrainDestination, viewModel: TrainingViewModel) -> some View {
        switch page {
        case .weekPlan: WeekPlanView(viewModel: viewModel)
        case .routines: RoutinesView(viewModel: viewModel)
        case .trainerProgram: TrainerProgramView()
        case .exerciseLibrary: ExerciseLibraryView(initialSearch: librarySearch)
        case .progress: ProgressChartsView()
        // Away mode is a sheet, not a page; the menu opens it directly.
        case .awayMode: EmptyView()
        }
    }

    private func open(_ request: TrainRoute) {
        if request.page == .awayMode {
            path = []
            showAwayMode = true
            return
        }
        librarySearch = request.exercise ?? ""
        path = [request.page]
    }

    // MARK: - Toolbar

    /// Everything else in Train: plan, routines, library, progress, history.
    private func moreMenu(viewModel: TrainingViewModel) -> some View {
        Menu {
            NavigationLink(value: TrainDestination.weekPlan) {
                Label("Week Plan", systemImage: "calendar")
            }

            NavigationLink(value: TrainDestination.routines) {
                Label("My Routines", systemImage: "list.bullet.rectangle")
            }

            NavigationLink(value: TrainDestination.trainerProgram) {
                Label("Trainer Program", systemImage: "person.crop.circle.badge.checkmark")
            }

            Button {
                showAwayMode = true
            } label: {
                Label("Away from the gym", systemImage: "airplane")
            }

            NavigationLink(value: TrainDestination.exerciseLibrary) {
                Label("Exercise Library", systemImage: "books.vertical")
            }

            NavigationLink(value: TrainDestination.progress) {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("More")
        .accessibilityHint("Open week plan, routines, trainer program, exercise library, or progress.")
    }
}
