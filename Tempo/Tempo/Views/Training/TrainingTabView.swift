import SwiftUI
import SwiftData

// MARK: - Training Tab Container
// Per BUILD_PLAN step 9.8 — Training tab root.
// Default: TodayWorkoutView. Navigation to: WeekPlanView, ExerciseLibraryView,
// ProgressChartsView, TrainingSettingsView.

struct TrainingTabView: View {

    @Environment(ServiceContainer.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TrainingViewModel?
    @State private var showActiveWorkout = false
    @State private var showSummary = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TrainingSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        NavigationLink {
                            if let viewModel {
                                WeekPlanView(viewModel: viewModel)
                            }
                        } label: {
                            Label("Week Plan", systemImage: "calendar")
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
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
            }
            .fullScreenCover(isPresented: $showActiveWorkout) {
                if let viewModel {
                    NavigationStack {
                        ActiveWorkoutView(viewModel: viewModel)
                    }
                }
            }
            .fullScreenCover(isPresented: $showSummary) {
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
