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
    @State
    private var viewModel: TrainingViewModel?
    @State
    private var showActiveWorkout = false
    @State
    private var showSummary = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    TodayWorkoutView(
                        viewModel: viewModel,
                        showActiveWorkout: $showActiveWorkout,
                        showSummary: $showSummary
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.tempoBgPrimary)
                }
            }
            .navigationTitle("Training")
            .tempoSettingsToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let viewModel {
                            NavigationLink {
                                WeekPlanView(viewModel: viewModel)
                            } label: {
                                Label("Week Plan", systemImage: "calendar")
                            }
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

                        NavigationLink {
                            WorkoutHistoryView()
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .accessibilityLabel("More")
                    .accessibilityHint("Open week plan, exercise library, progress, or history.")
                }
            }
            .fullScreenCover(isPresented: $showActiveWorkout) {
                if let viewModel {
                    NavigationStack {
                        ActiveWorkoutView(viewModel: viewModel)
                    }
                }
            }
            .fullScreenCover(isPresented: $showSummary, onDismiss: {
                showSummary = false
            }) {
                if let viewModel {
                    NavigationStack {
                        WorkoutSummaryView(viewModel: viewModel)
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TrainingViewModel(
                    trainingEngine: services.trainingEngine,
                    whoop: services.whoop,
                    healthKit: services.healthKit,
                    apiClient: services.apiClient,
                    calendarService: services.calendar
                )
            }
        }
        .onReceive(
            // Tier 3.3 — re-personalize the training week when the schedule
            // inputs change (football days / split edited in ScheduleEditorView).
            // Debounced 0.6s so a burst of chip toggles regenerates once, matching
            // the Nutrition observer. Skips while a workout is active so an edit
            // can't disturb an in-progress session (the guard also protects this).
            NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged)
                .debounce(for: .seconds(0.6), scheduler: DispatchQueue.main)
        ) { _ in
            guard let viewModel, !(viewModel.sessionState.isActive) else { return }
            viewModel.repersonalizeSchedule(modelContext: modelContext)
        }
        .alert(
            "Save failed",
            isPresented: Binding(
                get: { viewModel?.saveErrorMessage != nil },
                set: { if !$0 { viewModel?.saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.saveErrorMessage ?? "")
        }
        .onChange(of: viewModel?.sessionState) { _, newState in
            if case .summary = newState {
                // Persist completion the moment the session reaches summary —
                // NOT on the SAVE button. Previously history was written only
                // if the user tapped "SAVE & CLOSE"; swiping the summary away
                // (or any non-button exit) silently lost the whole session.
                // persistCompletion is idempotent, so the SAVE button calling
                // it again is a no-op.
                viewModel?.persistCompletion(modelContext: modelContext)
                showActiveWorkout = false
                showSummary = true
            } else if case .discarded = newState {
                // Discard → close the workout cover and reload today so the
                // session settles back to a fresh, restartable state (the day
                // was kept .planned). Driven from here, not a dismiss() inside
                // the cover, so teardown can't race the reset into a blank screen.
                showActiveWorkout = false
                showSummary = false
                if let viewModel {
                    Task { @MainActor in
                        await viewModel.loadToday(modelContext: modelContext)
                        viewModel.sessionState = .idle
                    }
                }
            }
        }
    }
}
