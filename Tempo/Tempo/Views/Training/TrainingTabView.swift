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
                    healthKit: services.healthKit
                )
            }
        }
        .onChange(of: viewModel?.sessionState) { _, newState in
            if case .summary = newState {
                showActiveWorkout = false
                showSummary = true
            }
        }
    }
}
