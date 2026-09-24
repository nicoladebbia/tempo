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
    /// Owned by ContentView so the app-level plan-freshness handler and this
    /// tab share one instance (one generation in flight, one spinner).
    @Bindable
    var viewModel: NutritionTabViewModel
    @State
    private var showDietaryProfileSetup = false
    @State
    private var showMealLogging = false

    /// Surfaces a plan-generation failure as a toast at the Nutrition root
    /// regardless of which sub-tab the user is on. Previously the only
    /// error indicator lived on the Plan view, so a failed auto-regen
    /// (triggered by a Training settings change) would happen silently if
    /// the user was on Today / Coach / Log / Pantry at the time.
    @State
    private var planErrorToast: ToastData?

    /// Presents the grocery list as a sheet. Driven by the "Open Grocery List"
    /// button in the pantry-gap alert, which previously only switched to the
    /// Plan tab and dead-ended (the list is a pushed view, not the tab itself).
    @State
    private var showGroceryListSheet = false

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
                // Loads today, then regenerates the plan if its training /
                // diet-profile inputs changed since it was built. The change
                // notifications themselves are handled app-wide in
                // ContentView, so they aren't lost when this tab was never
                // opened.
                viewModel.regenerateIfOutOfDate(
                    modelContext: modelContext,
                    whoop: services.whoop,
                    apiClient: services.apiClient,
                    notifications: services.notifications
                )
            }
            // Surface plan-generation failures (timeout / 5xx / decode) as
            // a toast at the Nutrition root. Previously these only showed
            // on the Plan sub-tab, so a silent failure on auto-regen would
            // leave the user wondering why nothing happened.
            .onChange(of: viewModel.planGenerationError) { _, newError in
                guard let newError, !newError.isEmpty else {
                    return
                }
                planErrorToast = ToastData(
                    message: "Couldn't generate plan: \(newError). Tap Generate on the Plan tab to retry.",
                    style: .error
                )
            }
            .tempoToast($planErrorToast)
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
            .sheet(isPresented: $showGroceryListSheet) {
                // Own NavigationStack so GroceryListView's title + toolbar
                // (Add Item / Sync with Pantry) render inside the sheet.
                NavigationStack {
                    GroceryListView(viewModel: viewModel)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { showGroceryListSheet = false }
                            }
                        }
                }
            }
            // Pantry-gap alert (Phase D) — same surface used by NutritionWeeklyPlanView,
            // wired here so generation triggered from profile setup also surfaces gaps.
            .alert(
                "Shopping Gap",
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
                // Missing ingredients are things to BUY → the grocery list,
                // which lives on the Plan tab. (Was incorrectly routing to the
                // Pantry, where you'd only add things you already have.)
                Button("Open Grocery List") {
                    viewModel.pantryGapAlert = nil
                    // Actually open the grocery list (a sheet), not just switch
                    // tabs. The list lives behind a NavigationLink on the Plan
                    // tab, so switching tabs alone left the user staring at the
                    // plan with nothing opened.
                    showGroceryListSheet = true
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
            NutritionTodayView(viewModel: viewModel)
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
    NutritionTabView(viewModel: NutritionTabViewModel())
        .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
