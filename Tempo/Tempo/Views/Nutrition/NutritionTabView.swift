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
    @State
    private var showSettings = false
    /// Segment taps, for the selection haptic.
    @State
    private var sectionTaps = 0

    /// Something of Fuel's own is presented over the page: the field stops.
    private var isCovered: Bool {
        showMealLogging || showScan || showSettings
    }

    var body: some View {
        NavigationStack {
            // The date, the page name and the section switcher stay put; the
            // sections scroll underneath them with a soft edge.
            VStack(spacing: 0) {
                switch viewModel.loadState {
                case .loading:
                    // The shape of the page that is coming, not a lone spinner.
                    VStack(spacing: Tide.s4) {
                        FuelSkeletonRows(count: 3).tideCard()
                        FuelSkeletonRows(count: 2).tideCard()
                    }
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                case let .error(message):
                    errorState(message)

                case .loaded:
                    sectionContent
                }
            }
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: Tide.s3) {
                    header
                    sectionPicker
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s3)
                .background(alignment: .top) {
                    // Ink that fades out under the switcher, so the cards
                    // scrolling beneath never read through the title.
                    LinearGradient(
                        stops: [
                            .init(color: Tide.ink.opacity(0.97), location: 0),
                            .init(color: Tide.ink.opacity(0.95), location: 0.85),
                            .init(color: Tide.ink.opacity(0), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .padding(.bottom, -Tide.s3)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                }
            }
            .tidePage(energy: 1)
            .toolbar(.hidden, for: .navigationBar)
            .tempoSettingsToolbar(isPresented: $showSettings)
            .tideCovered(isCovered)
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
            .fuelToast($planErrorToast)
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
            // Pantry-gap question (Phase D) — same surface used by NutritionWeeklyPlanView,
            // wired here so generation triggered from profile setup also surfaces gaps.
            // A page of its own instead of a system alert: the answer sits under the thumb.
            .sheet(item: Binding(
                get: { viewModel.pantryGapAlert },
                set: { viewModel.pantryGapAlert = $0 }
            )) { gap in
                FuelDecisionSheet(
                    icon: "cart.badge.plus",
                    title: "Shopping gap",
                    message: gap.summary,
                    primaryTitle: "Open Grocery List",
                    // Missing ingredients are things to BUY → the grocery list,
                    // which lives in Kitchen. (Was incorrectly routing to the
                    // Pantry, where you'd only add things you already have.)
                    primary: {
                        viewModel.pantryGapAlert = nil
                        viewModel.openKitchen(.groceries)
                    },
                    cancelTitle: "Dismiss",
                    cancel: { viewModel.pantryGapAlert = nil }
                )
                .environment(\.tideInsidePage, false)
            }
        }
        // "Lunch logged. 640 kcal." with Undo, after a meal was saved anywhere in
        // Fuel. Outermost, so the sheets above the page (the capture screen) know a
        // host is below them and close at once.
        .fuelLogToastHost()
    }

    // MARK: - Section Picker

    /// The date and the page name, with Settings. Calm: nothing here competes
    /// with the numbers below.
    private var header: some View {
        HStack(alignment: .center, spacing: Tide.s2) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .tideLabel()
                Text("Fuel")
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tide.s2)
            FuelIconButton(systemImage: "gearshape.fill", label: "Settings") {
                HapticManager.lightImpact()
                showSettings = true
            }
            .accessibilityIdentifier("fuel.settings")
        }
    }

    /// Today, Plan, Log, Kitchen, Coach: the system's glass segmented control.
    private var sectionPicker: some View {
        Picker("Section", selection: $viewModel.selectedTab) {
            ForEach(NutritionSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.selectedTab) { _, _ in
            sectionTaps += 1
        }
        .sensoryFeedback(.selection, trigger: sectionTaps)
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.selectedTab {
        case .today:
            NutritionTodayView(viewModel: viewModel, onLogMeal: { showMealLogging = true }, onScan: {
                // Receipt mode needs the Kitchen services; attaching is idempotent.
                viewModel.attachPhase7Services(modelContext: modelContext, services: services)
                resumedScan = nil
                showScan = true
            })
            .firstTip("fuel.today", "Log a meal, scan food or add water with the buttons up top, and tap any number to see how it is worked out.")
        case .plan:
            VStack(spacing: 0) {
                planQuickLinks
                NutritionWeeklyPlanView(viewModel: viewModel)
            }
            .firstTip("fuel.plan", "Tap a day to open its meals, then tap a meal to see the recipe and mark it eaten.")
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
        let recipes = NavigationLink {
            RecipeSuggestionsView(viewModel: viewModel)
        } label: {
            Label("Recipes", systemImage: "fork.knife.circle.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
        let review = NavigationLink {
            WeeklyMealReviewView()
        } label: {
            Label("Review", systemImage: "text.bubble.fill")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)

        // Side by side while they fit, stacked at large text sizes.
        return GlassEffectContainer(spacing: Tide.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) {
                    recipes
                    review
                }
                VStack(spacing: Tide.s2) {
                    recipes
                    review
                }
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.bottom, Tide.s3)
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Tide.s4) {
            Spacer()
            FuelEmptyState(icon: "exclamationmark.triangle.fill", title: "Fuel did not load", message: message) {
                Button("Retry") {
                    viewModel.loadToday(modelContext: modelContext)
                }
                .buttonStyle(.tidePrimary)
            }
            .padding(.horizontal, Tide.edge)
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    NutritionTabView(viewModel: NutritionTabViewModel())
        .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
