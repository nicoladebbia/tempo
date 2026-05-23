//
// NutritionTabView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Nutrition Tab View

// Full nutrition tab with segmented sections: Today, Plan, Log, Coach.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct NutritionTabView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var viewModel = NutritionTabViewModel()
    @State
    private var showDietaryProfileSetup = false
    @State
    private var showMealLogging = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Segmented control
                    sectionPicker
                        .padding(.horizontal, TempoSpacing.screenEdge)
                        .padding(.vertical, TempoSpacing.sm)

                    // Content
                    switch viewModel.loadState {
                    case .loading:
                        Spacer()
                        ProgressView()
                            .tint(Color.tempoSignal)
                        Spacer()

                    case let .error(message):
                        errorState(message)

                    case .loaded:
                        sectionContent
                    }
                }
            }
            .navigationTitle("FUEL")
            .navigationBarTitleDisplayMode(.inline)
            .tempoSettingsToolbar()
            .task {
                viewModel.loadToday(modelContext: modelContext)
            }
            .sheet(isPresented: $showDietaryProfileSetup) {
                DietaryProfileSetupView(onSaveAndGenerate: { _ in
                    // Switch to Plan tab and auto-generate
                    viewModel.loadToday(modelContext: modelContext)
                    viewModel.selectedTab = .plan
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        viewModel.generatePlan(
                            modelContext: modelContext,
                            whoop: services.whoop,
                            apiClient: services.apiClient,
                            healthKit: services.healthKit,
                            notifications: services.notifications
                        )
                    }
                })
            }
            .sheet(isPresented: $showMealLogging) {
                MealLoggingView()
                    .onDisappear {
                        viewModel.loadToday(modelContext: modelContext)
                    }
            }
            // Pantry-gap alert (Phase D) — same surface used by NutritionWeeklyPlanView,
            // wired here so generation triggered from profile setup also surfaces gaps.
            .alert(
                "Pantry Gap",
                isPresented: Binding(
                    get: { viewModel.pantryGapAlert != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.pantryGapAlert = nil
                        }
                    }
                ),
                presenting: viewModel.pantryGapAlert
            ) { _ in
                Button("Open Pantry") {
                    viewModel.selectedTab = .pantry
                    viewModel.pantryGapAlert = nil
                }
                Button("Dismiss", role: .cancel) {
                    viewModel.pantryGapAlert = nil
                }
            } message: { alert in
                Text(alert.summary)
            }
        }
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        Picker("Section", selection: $viewModel.selectedTab) {
            ForEach(NutritionSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.selectedTab) { _, _ in
            HapticManager.selection()
        }
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.selectedTab {
        case .today:
            NutritionTodayView(viewModel: viewModel, showMealLogging: $showMealLogging)
        case .plan:
            VStack(spacing: 0) {
                planQuickLinks
                NutritionWeeklyPlanView(viewModel: viewModel)
            }
        case .log:
            NutritionLogView(viewModel: viewModel, showMealLogging: $showMealLogging)
        case .coach:
            NutritionCoachView(viewModel: viewModel)
        case .pantry:
            PantryView(viewModel: viewModel)
        }
    }

    /// Quick-link strip shown above the meal-plan tab — entry points to
    /// recipe suggestions and the grocery list. These are short workflows
    /// that don't need their own segmented-control slots.
    private var planQuickLinks: some View {
        HStack(spacing: TempoSpacing.sm) {
            NavigationLink {
                RecipeSuggestionsView(viewModel: viewModel)
            } label: {
                Label("Recipes", systemImage: "fork.knife.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            NavigationLink {
                GroceryListView(viewModel: viewModel)
            } label: {
                Label("Grocery", systemImage: "cart.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            NavigationLink {
                WeeklyMealReviewView()
            } label: {
                Label("Review", systemImage: "text.bubble.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.sm)
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoWarning)

            Text("Failed to Load")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.xl)

            Button {
                viewModel.loadToday(modelContext: modelContext)
            } label: {
                Text("Retry")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.tempoTextInverse)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.tempoSignal)
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    NutritionTabView()
        .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
