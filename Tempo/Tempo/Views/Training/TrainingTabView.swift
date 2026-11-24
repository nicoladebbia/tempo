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

    var body: some View {
        // The session (view model and its screens) is owned by the app, not
        // by this tab: Today and the Move detail drive the same one.
        @Bindable
        var session = services.workoutSession
        let viewModel = session.viewModel
        return NavigationStack {
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

    // MARK: - Toolbar

    /// Everything else in Train: plan, routines, library, progress, history.
    private func moreMenu(viewModel: TrainingViewModel) -> some View {
        Menu {
            NavigationLink {
                WeekPlanView(viewModel: viewModel)
            } label: {
                Label("Week Plan", systemImage: "calendar")
            }

            NavigationLink {
                RoutinesView(viewModel: viewModel)
            } label: {
                Label("My Routines", systemImage: "list.bullet.rectangle")
            }

            NavigationLink {
                TrainerProgramView()
            } label: {
                Label("Trainer Program", systemImage: "person.crop.circle.badge.checkmark")
            }

            Button {
                showAwayMode = true
            } label: {
                Label("Away from the gym", systemImage: "airplane")
            }

            NavigationLink {
                ExerciseLibraryView()
            } label: {
                Label("Exercise Library", systemImage: "books.vertical")
            }

            NavigationLink {
                ProgressChartsView()
            } label: {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("More")
        .accessibilityHint("Open week plan, routines, trainer program, exercise library, or progress.")
    }
}
