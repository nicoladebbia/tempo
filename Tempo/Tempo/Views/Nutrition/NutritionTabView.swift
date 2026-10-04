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

// Full nutrition tab with segmented sections: Today, Plan, Log, Kitchen, Coach.
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
    /// Today's Scan button: the universal scanner with all four modes.
    @State
    private var showScan = false
    /// Set while the scanner is the one reopened after a trip to iOS Settings.
    @State
    private var resumedScan: ScanResumeRecord?
    @State
    private var showMealLogging = false
    /// Today's Quick Log sheet (type, Confirm Meal opens on top of it).
    @State
    private var showQuickLog = false
    /// "Breakfast logged. 420 kcal." after a meal was confirmed anywhere in Nutrition.
    @State
    private var mealLogToast: ToastData?

    /// Surfaces a plan-generation failure as a toast at the Nutrition root
    /// regardless of which sub-tab the user is on. Previously the only
    /// error indicator lived on the Plan view, so a failed auto-regen
    /// (triggered by a Training settings change) would happen silently if
    /// the user was on Today / Coach / Log / Pantry at the time.
    @State
    private var planErrorToast: ToastData?
    /// Pro / AI-off blocker for a plan build started outside the Plan tab
    /// (the Plan tab shows its own card).
    @State
    private var planBlockerAlert: AIBlocker?
    /// Same, for Coach meal ideas.
    @State
    private var mealIdeasBlocker: AIBlocker?

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
            // A meal was changed or deleted from another screen (meal detail,
            // Watch, Log tab): drop a row about to be deleted BEFORE the model
            // goes away, then re-read today's meals + presets.
            .onReceive(NotificationCenter.default.publisher(for: .tempoMealWillBeRemoved)) { note in
                if let id = note.userInfo?["id"] as? UUID {
                    viewModel.dropFromToday(mealID: id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoNutritionLogged)) { _ in
                viewModel.refreshAfterMealChange(modelContext: modelContext)
            }
            .task {
                // Loads today and flags the plan when its training / diet-profile
                // inputs changed since it was built (Today then asks whether to
                // update — it never rebuilds on its own). The change
                // notifications themselves are handled app-wide in
                // ContentView, so they aren't lost when this tab was never
                // opened.
                viewModel.checkPlanFreshness(modelContext: modelContext)
            }
            // Surface plan-generation failures (timeout / 5xx / decode) as
            // a toast at the Nutrition root. Previously these only showed
            // on the Plan sub-tab, so a silent failure on auto-regen would
            // leave the user wondering why nothing happened.
            .onChange(of: viewModel.planGenerationError) { _, newError in
                guard let newError, !newError.isEmpty else {
                    return
                }
                if let blocker = viewModel.planGenerationBlocker {
                    if viewModel.selectedTab != .plan {
                        planBlockerAlert = blocker.aiBlocker
                    }
                    return
                }
                planErrorToast = ToastData(
                    message: "Couldn't generate plan: \(newError). Tap Generate on the Plan tab to retry.",
                    style: .error
                )
            }
            .tempoToast($planErrorToast)
            .tempoToast($mealLogToast)
            .onReceive(NotificationCenter.default.publisher(for: .tempoMealLogToast)) { note in
                guard let message = note.userInfo?["message"] as? String else {
                    return
                }
                let isError = note.userInfo?["error"] as? Bool ?? false
                mealLogToast = ToastData(message: message, style: isError ? .error : .success)
            }
            .sheet(isPresented: $showQuickLog) {
                QuickLogSheet()
            }
            .onChange(of: viewModel.mealSuggestionBlocker) { _, blocker in
                if let blocker {
                    mealIdeasBlocker = blocker
                }
            }
            .aiBlockerAlert($mealIdeasBlocker) {
                viewModel.getMealSuggestions(apiClient: services.apiClient)
            }
            .aiBlockerAlert($planBlockerAlert) {
                viewModel.planGenerationBlocker = nil
                viewModel.planGenerationError = nil
                viewModel.rebuildRestOfWeek(modelContext: modelContext, services: services)
            }
            .sheet(isPresented: $showMealLogging) {
                MealLoggingView()
                    .onDisappear {
                        viewModel.loadToday(modelContext: modelContext)
                    }
            }
            .fullScreenCover(isPresented: $showScan, onDismiss: {
                // A meal-photo log from Scan lands in today's meals.
                viewModel.loadToday(modelContext: modelContext)
            }) {
                Group {
                    if resumedScan?.contextKind == .foodCheck {
                        UniversalScanView(context: .foodCheck, initialMode: resumedScan?.scanMode)
                    } else {
                        // A meal photo is confirmed in the Confirm Meal sheet
                        // right on top of the scanner: no tab switch.
                        UniversalScanView(context: .today(), initialMode: resumedScan?.scanMode)
                    }
                }
                .environment(\.scanResumeSection, viewModel.selectedTab)
            }
            .onChange(of: viewModel.scanResume, initial: true) { _, record in
                guard let record else {
                    return
                }
                viewModel.scanResume = nil
                resumedScan = record
                viewModel.attachPhase7Services(modelContext: modelContext, services: services)
                showScan = true
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
                // which lives in Kitchen. (Was incorrectly routing to the
                // Pantry, where you'd only add things you already have.)
                Button("Open Grocery List") {
                    viewModel.pantryGapAlert = nil
                    viewModel.openKitchen(.groceries)
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
            NutritionTodayView(viewModel: viewModel, onQuickLog: { showQuickLog = true }, onScan: {
                // Receipt mode needs the Kitchen services; attaching is idempotent.
                viewModel.attachPhase7Services(modelContext: modelContext, services: services)
                resumedScan = nil
                showScan = true
            })
        case .plan:
            VStack(spacing: 0) {
                planQuickLinks
                NutritionWeeklyPlanView(viewModel: viewModel)
            }
        case .log:
            NutritionLogView(viewModel: viewModel, showMealLogging: $showMealLogging)
        case .coach:
            NutritionCoachView(viewModel: viewModel)
        case .kitchen:
            KitchenView(viewModel: viewModel)
        }
    }

    /// Quick-link strip shown above the meal-plan tab — entry points to
    /// recipe suggestions and the weekly review. These are short workflows
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
