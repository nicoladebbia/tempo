//
// DashboardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @State
    private var viewModel: DashboardViewModel?
    @State
    private var hasAppeared = false
    @State
    private var showNutriTrackConnect = false
    @State
    private var showMealLogging = false
    @State
    private var showWhoopConnect = false
    @State
    private var showSettings = false
    @State
    private var showNotifications = false
    @State
    private var showInsightDetail = false
    @State
    private var showNonNegotiableSetup = false
    @State
    private var showScoreBreakdown = false
    @State
    private var activeMilestone: MilestoneService.Milestone?
    @State
    private var showMilestoneCelebration = false
    @State
    private var showProgressReport = false
    @AppStorage("healthKitAuthorized")
    private var healthKitAuthorized = false
    @AppStorage("hasCompletedSetup")
    private var hasCompletedSetup = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary
                    .ignoresSafeArea()

                if let viewModel {
                    switch viewModel.loadState {
                    case .loading where !hasAppeared:
                        DashboardLoadingView()

                    case let .error(message) where !hasAppeared:
                        ErrorStateView(
                            title: "Sync failed.",
                            message: message,
                            retryAction: {
                                Task {
                                    await viewModel.refresh()
                                    viewModel.refreshTrainingStatus(modelContext: modelContext)
                                    viewModel.refreshAccountability(modelContext: modelContext)
                                }
                            }
                        )

                    default:
                        dashboardContent(viewModel)
                    }
                } else {
                    DashboardLoadingView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            if viewModel == nil {
                let vm = DashboardViewModel(services: services)
                // Query UserProfile and populate userName
                let descriptor = FetchDescriptor<UserProfile>()
                if let profile = try? modelContext.fetch(descriptor).first {
                    vm.setUserName(profile.displayName)
                }
                viewModel = vm
                // Validate Whoop connection BEFORE fetching data — prevents race condition
                // where refresh() checks connectionState before tokens are verified
                await services.whoop.checkConnectionOnLaunch()

                // Update display name from Whoop profile if still default
                let descriptor2 = FetchDescriptor<UserProfile>()
                if let profile = try? modelContext.fetch(descriptor2).first,
                   profile.displayName == "Athlete",
                   let whoopService = services.whoop as? WhoopService,
                   let firstName = whoopService.profileFirstName, !firstName.isEmpty
                {
                    let fullName = [firstName, whoopService.profileLastName].compactMap(\.self).joined(separator: " ")
                    profile.displayName = fullName
                    profile.updatedAt = Date()
                    try? modelContext.save()
                    vm.setUserName(fullName)
                }

                // Load deload frequency from settings
                let settingsDescriptor = FetchDescriptor<UserSettings>()
                if let settings = try? modelContext.fetch(settingsDescriptor).first {
                    vm.setDeloadFrequency(settings.deloadFrequencyWeeks)
                }

                // Load persisted score history for sparkline
                vm.loadScoreHistory(modelContext: modelContext)

                await vm.refresh()
                vm.refreshTrainingStatus(modelContext: modelContext)
                vm.refreshAccountability(modelContext: modelContext)

                // Persist today's score and reload trend
                vm.persistDailyScore(modelContext: modelContext)
                vm.loadScoreHistory(modelContext: modelContext)

                // Fetch weather (non-blocking)
                await vm.fetchWeather()

                hasAppeared = true

                // Check retention milestones
                if let milestone = MilestoneService.checkMilestone(modelContext: modelContext) {
                    activeMilestone = milestone
                    showMilestoneCelebration = true
                }
            }
        }
        .fullScreenCover(isPresented: $showMilestoneCelebration) {
            if let milestone = activeMilestone {
                MilestoneCelebrationView(
                    milestone: milestone,
                    onDismiss: { showMilestoneCelebration = false },
                    onShowProgress: milestone == .day30 ? {
                        showMilestoneCelebration = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showProgressReport = true
                        }
                    } : nil
                )
            }
        }
        .sheet(isPresented: $showProgressReport) {
            ProgressReportView()
        }
        .sheet(isPresented: $showNutriTrackConnect) {
            NutriTrackConnectView(
                nutriTrackService: services.nutriTrack,
                onConnected: {
                    Task {
                        await viewModel?.refresh()
                    }
                }
            )
        }
        .sheet(isPresented: $showMealLogging) {
            MealLoggingView()
        }
        .sheet(isPresented: $showWhoopConnect, onDismiss: {
            Task {
                await viewModel?.refresh()
                viewModel?.refreshTrainingStatus(modelContext: modelContext)
            }
        }) {
            NavigationStack {
                WhoopConnectionView()
            }
        }
        .onChange(of: services.whoop.connectionState) { oldState, newState in
            // Auto-refresh when Whoop connects mid-session (e.g. after OAuth completes)
            if case .connected = newState, oldState != .connected {
                Task {
                    await viewModel?.refresh()
                    viewModel?.refreshTrainingStatus(modelContext: modelContext)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                DashboardSettingsView()
            }
        }
        .sheet(isPresented: $showNotifications) {
            NavigationStack {
                NotificationSettingsView()
            }
        }
        .sheet(isPresented: $showNonNegotiableSetup, onDismiss: {
            // Refresh accountability data so banner detects new non-negotiables
            viewModel?.refreshAccountability(modelContext: modelContext)
        }) {
            NavigationStack {
                NonNegotiableSetupView()
            }
        }
    }

    // MARK: - Setup Tracking

    /// True when at least 2 data sources are connected (Whoop, NutriTrack, HealthKit).
    private var hasConnectedSources: Bool {
        var count = 0
        if services.whoop.connectionState == .connected {
            count += 1
        }
        if case .connected = services.nutriTrack.connectionState {
            count += 1
        }
        if healthKitAuthorized {
            count += 1
        }
        return count >= 2
    }

    // MARK: - Dashboard Content

    private func dashboardContent(_ vm: DashboardViewModel) -> some View {
        // Edge-to-edge layout. Header sits just below the status bar, the
        // 2x2 grid fills the rest of the screen (extending under the
        // floating tab bar). No black bars on top or bottom.
        VStack(spacing: 0) {
            headerRow(vm)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.sm)
                .padding(.bottom, TempoSpacing.md)

            quadrantGrid(vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pull the entire layout up into the nav-bar phantom space iOS 26
        // reserves but `.toolbar(.hidden)` can't fully reclaim, and down
        // under the home-indicator safe area so the last row of cards
        // reaches the bottom edge.
        .padding(.top, -56)
        .padding(.bottom, -34)
        .sheet(isPresented: $showScoreBreakdown) {
            ScoreBreakdownSheet(vm: vm)
        }
    }

    // MARK: - Header

    private func headerRow(_ vm: DashboardViewModel) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.greeting)
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(vm.formattedDate.uppercased())
                        .font(.tempoCaption1)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .tracking(0.5)

                    // Weather indicator
                    if let weather = vm.weather {
                        Text("\u{00B7}")
                            .font(.tempoCaption1)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.tempoTextTertiary)
                        HStack(spacing: 3) {
                            Image(systemName: weather.conditionSymbol)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.tempoTextSecondary)
                            Text(weather.formattedTemperature)
                                .font(.tempoCaption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }

                    if !vm.formattedLastSync.isEmpty {
                        Text("\u{00B7}")
                            .font(.tempoCaption1)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text(vm.formattedLastSync)
                            .font(.tempoCaption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }

            Spacer()

            // Score pill — compact inline display, tap for breakdown
            if let score = vm.dailyScore {
                Button {
                    showScoreBreakdown = true
                } label: {
                    HStack(spacing: 6) {
                        ScoreRingView(
                            score: Double(score),
                            maxScore: 100,
                            size: 28,
                            strokeWidth: 3
                        )
                        Text("\(score)")
                            .font(.tempoDataMedium)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 4) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.tempoBody)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .frame(width: 34, height: 34)

                Button {
                    showNotifications = true
                } label: {
                    Image(systemName: "bell")
                        .font(.tempoBody)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .frame(width: 34, height: 34)
            }
        }
        .padding(.top, TempoSpacing.sm)
    }

    // MARK: - Quadrant Grid

    private func quadrantGrid(_ vm: DashboardViewModel) -> some View {
        // Two rows of two equal-size cards. Each row fills half the parent
        // height; cards inside fill their row. The grid expands to whatever
        // height the parent gives it.
        VStack(spacing: TempoSpacing.cardGap) {
            HStack(spacing: TempoSpacing.cardGap) {
                NavigationLink(destination: BodyQuadrantDetailView(data: vm.body)) {
                    bodyCard(vm.body)
                }
                .buttonStyle(.plain)

                NavigationLink(destination: MoveQuadrantDetailView(data: vm.move)) {
                    moveCard(vm.move)
                }
                .buttonStyle(.plain)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: TempoSpacing.cardGap) {
                NavigationLink(destination: DailyNutritionSummaryView(fuelData: vm.fuel, onAddHydration: { ml in
                    vm.addHydration(ml)
                })) {
                    fuelCard(vm.fuel)
                }
                .buttonStyle(.plain)

                NavigationLink(destination: MindQuadrantDetailView(data: vm.mind)) {
                    mindCard(vm.mind)
                }
                .buttonStyle(.plain)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Body Card

    private func bodyCard(_ data: BodyQuadrantData) -> some View {
        cardShell(label: "BODY") {
            if data.isConnected || services.whoop.connectionState == .connected {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text(data.formattedRecovery)
                        .font(.tempoXPDisplay)
                        .foregroundStyle(data.recoveryZone?.color ?? Color.tempoTextPrimary)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: data.formattedRecovery)

                    Text("Recovery")
                        .font(.tempoCaption1)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.tempoTextTertiary)

                    Divider().opacity(0.3)

                    VStack(alignment: .leading, spacing: 6) {
                        miniMetric(label: "HRV", value: data.formattedHRV)
                        miniMetric(label: "RHR", value: data.formattedRHR)
                        miniMetric(label: "Sleep", value: data.formattedSleep)
                    }

                    if let strain = data.strain {
                        strainIndicator(strain)
                    }
                }
            } else {
                connectPrompt(
                    icon: "waveform.path.ecg",
                    message: "Connect Whoop",
                    action: { showWhoopConnect = true }
                )
            }
        }
    }

    // MARK: - Fuel Card

    private func fuelCard(_ data: FuelQuadrantData) -> some View {
        cardShell(label: "FUEL") {
            if data.isConnected {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(data.formattedCalories)
                            .font(.tempoScoreDisplaySmall)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: data.formattedCalories)
                        Text("kcal")
                            .font(.tempoCaption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    progressBar(progress: data.calorieProgress, color: Color.tempoViolet)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: data.calorieProgress)

                    Text("of \(data.formattedCalorieTarget) target")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)

                    Divider().opacity(0.3)

                    // Macro mini rings with color-coded status (Task 2)
                    HStack(spacing: 6) {
                        fuelCardMacroRing(
                            letter: "P",
                            current: data.proteinGrams ?? 0,
                            target: data.proteinTarget ?? 180,
                            color: .cyan,
                            status: data.proteinStatus
                        )
                        fuelCardMacroRing(
                            letter: "C",
                            current: data.carbsGrams ?? 0,
                            target: data.carbsTarget ?? 280,
                            color: .yellow,
                            status: data.carbsStatus
                        )
                        fuelCardMacroRing(
                            letter: "F",
                            current: data.fatGrams ?? 0,
                            target: data.fatTarget ?? 80,
                            color: .orange,
                            status: data.fatStatus
                        )
                    }

                    // Hydration quick display (Task 4)
                    if data.hydrationMl > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.tempoElectric)
                            Text(data.formattedHydration)
                                .font(.tempoCaption2)
                                .fontWeight(.medium)
                                .foregroundStyle(
                                    data.hydrationProgress >= 0.7
                                        ? Color.tempoSuccess : Color.tempoTextSecondary
                                )
                        }
                    }

                    // Nutrition mode badge (Task 1)
                    if data.nutritionMode != .standard {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(fuelModeBadgeColor(data.nutritionMode))
                                .frame(width: 5, height: 5)
                            Text(fuelModeBadgeText(data.nutritionMode))
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(fuelModeBadgeColor(data.nutritionMode))
                        }
                    }

                    Text(data.formattedMeals)
                        .font(.tempoCaption2)
                        .fontWeight(.medium)
                        .foregroundStyle(
                            (data.mealsLogged ?? 0) >= (data.mealsPlanned ?? 1)
                                ? Color.tempoSuccess : Color.tempoTextSecondary
                        )
                }
            } else {
                connectPrompt(
                    icon: "fork.knife",
                    message: "Add Meal",
                    buttonText: "Add",
                    action: { showMealLogging = true }
                )
            }
        }
    }

    private func fuelCardMacroRing(
        letter: String,
        current: Int,
        target: Int,
        color: Color,
        status: NutritionEngine.MacroStatus
    ) -> some View {
        let progress = target > 0 ? Double(current) / Double(target) : 0
        let ringColor: Color = switch status {
        case .onTrack: .tempoSuccess
        case .behind: .tempoWarning
        case .over: .tempoError
        }

        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle()
                    .trim(from: 0, to: min(progress, 1.0))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(letter)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .frame(width: 24, height: 24)

            Text("\(current)g")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fuelModeBadgeColor(_ mode: NutritionMode) -> Color {
        switch mode {
        case .repair: .tempoError
        case .fuel: .tempoSuccess
        case .rest: .tempoElectric
        case .standard: .tempoTextTertiary
        }
    }

    private func fuelModeBadgeText(_ mode: NutritionMode) -> String {
        switch mode {
        case .repair: "REPAIR"
        case .fuel: "FUEL UP"
        case .rest: "REST"
        case .standard: ""
        }
    }

    // MARK: - Mind Card

    private func mindCard(_ data: MindQuadrantData) -> some View {
        cardShell(label: "MIND") {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text(data.formattedStudyTime)
                    .font(.tempoXPDisplay)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: data.formattedStudyTime)

                if data.studyMinutesToday >= data.studyTargetMinutes, data.studyTargetMinutes > 0 {
                    Text("Target hit")
                        .font(.tempoCaption1)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.tempoSuccess)
                } else {
                    Text("of \(data.formattedStudyTarget) target")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                progressBar(
                    progress: data.studyProgress,
                    color: Color.tempoElectric
                )
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: data.studyProgress)

                if let exam = data.exams.first {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.tempoModuleTag)
                        Text("\(exam.name) \(exam.formattedCountdown)")
                            .font(.tempoCaption2)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .foregroundStyle(examCountdownColor(exam.daysUntil))
                }

                if data.currentStreakDays >= 2 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.tempoModuleTag)
                            .foregroundStyle(Color.tempoAmber)
                        Text("\(data.formattedStreak) streak")
                            .font(.tempoCaption2)
                            .fontWeight(.medium)
                            .foregroundStyle(
                                data.currentStreakDays >= 7
                                    ? Color.tempoAmber : Color.tempoTextSecondary
                            )
                    }
                }
            }
        }
    }

    // MARK: - Move Card

    private func moveCard(_ data: MoveQuadrantData) -> some View {
        cardShell(label: "MOVE") {
            if data.isConnected || healthKitAuthorized {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    workoutStatus(data)

                    Divider().opacity(0.3)

                    VStack(alignment: .leading, spacing: 6) {
                        miniMetricAnimated(
                            label: "Steps",
                            value: data.formattedSteps,
                            valueColor: stepsColor(data.steps, target: data.stepsTarget)
                        )
                        miniMetricAnimated(
                            label: "Active",
                            value: data.formattedActiveCalories,
                            valueColor: .tempoTextPrimary
                        )
                    }

                    progressBar(
                        progress: data.stepsProgress,
                        color: Color.tempoAmber
                    )
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: data.stepsProgress)

                    HStack {
                        Spacer()
                        Text("\(NumberFormatter.localizedString(from: NSNumber(value: data.stepsTarget), number: .decimal)) goal")
                            .font(.tempoModuleTag)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            } else {
                connectPrompt(
                    icon: "heart.text.square",
                    message: "Authorize Health",
                    action: {
                        Task {
                            try? await services.healthKit.requestAuthorization()
                            healthKitAuthorized = true
                            await viewModel?.refresh()
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func workoutStatus(_ data: MoveQuadrantData) -> some View {
        switch data.workoutStatus {
        case .completed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoSuccess)
                Text("Done")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoSuccess)
            }
            if let name = data.workoutName {
                Text("\(name) — \(data.formattedWorkoutDuration)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
            }
        case .planned:
            Text(data.workoutName ?? "Workout")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)
            Text("Planned for today")
                .font(.tempoCaption2)
                .fontWeight(.medium)
                .foregroundStyle(Color.tempoAmber)
            if let duration = data.workoutDurationMinutes {
                Text("~\(duration) min")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        case .restDay:
            Text("Rest Day")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextSecondary)
            Text("Recovery is training.")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .italic()
        case .none:
            Text("No workout")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextTertiary)
            Text("Add one or skip.")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Non-Negotiables

    private func nonNegotiablesSection(_ vm: DashboardViewModel) -> some View {
        Group {
            if vm.nonNegotiablesTotal > 0 {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    HStack {
                        Text("\(vm.nonNegotiablesDone)/\(vm.nonNegotiablesTotal) done")
                            .font(.tempoSubheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Spacer()

                        Image(systemName: vm.nonNegotiablesDone >= vm.nonNegotiablesTotal ? "lock.open.fill" : "lock.fill")
                            .font(.tempoFootnote)
                            .foregroundStyle(
                                vm.nonNegotiablesDone >= vm.nonNegotiablesTotal
                                    ? Color.tempoSuccess : Color.tempoTextTertiary
                            )
                    }

                    progressBar(
                        progress: vm.nonNegotiableProgress,
                        color: vm.nonNegotiablesDone >= vm.nonNegotiablesTotal
                            ? Color.tempoSuccess : Color.tempoSignal,
                        height: 4
                    )

                    FlowLayout(spacing: 10, lineSpacing: 6) {
                        ForEach(vm.nonNegotiables) { item in
                            nonNegotiablePill(item)
                        }
                    }
                }
            } else {
                VStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "lock.fill")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextTertiary)

                    Text("Set your non-negotiables")
                        .font(.tempoSubheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text("Daily commitments you won't break")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)

                    Button {
                        showNonNegotiableSetup = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.tempoCaption2)
                            Text("Add")
                                .font(.tempoFootnote)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.tempoSignal)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func nonNegotiablePill(_ item: NonNegotiableItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.tempoCaption1)
                .foregroundStyle(item.isCompleted ? Color.tempoSuccess : Color.tempoTextTertiary)

            Text(item.title)
                .font(.tempoCaption1)
                .foregroundStyle(item.isCompleted ? Color.tempoTextSecondary : Color.tempoTextPrimary)
                .strikethrough(item.isCompleted)
        }
    }

    // MARK: - Quick Actions

    // Context-aware action buttons. Max 2 visible at a time.

    @ViewBuilder
    private func quickActionsRow(_ vm: DashboardViewModel) -> some View {
        let actions = vm.quickActions
        if !actions.isEmpty {
            VStack(spacing: TempoSpacing.sm) {
                ForEach(actions) { action in
                    Button {
                        services.appState.activeTab = action.targetTab
                        if action.targetTab == .dashboard {
                            // Special handling for "Log a Meal" — open meal logging sheet
                            showMealLogging = true
                        }
                    } label: {
                        HStack(spacing: TempoSpacing.sm) {
                            Image(systemName: action.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(action.color)
                                .frame(width: 28, height: 28)
                                .background(action.color.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text(action.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.tempoTextPrimary)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(action.color)
                        }
                        .padding(.horizontal, TempoSpacing.cardPadding)
                        .padding(.vertical, 12)
                        .background(Color.tempoSurfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // Weather recommendation banner
        if let weather = vm.weather, let recommendation = weather.recommendation {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: weather.conditionSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoElectric)

                Text(recommendation)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tempoTextSecondary)

                Spacer()
            }
            .padding(.horizontal, TempoSpacing.cardPadding)
            .padding(.vertical, 10)
            .background(Color.tempoElectric.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
    }

    // MARK: - Arena Quick Access

    private func arenaQuickAccessCard() -> some View {
        NavigationLink(destination: ArenaTabView()) {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.tempoSignal)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ARENA")
                        .font(.tempoCaption1)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .tracking(0.5)
                    Text("XP, levels & challenges")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.md)
            .background(Color.tempoBgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Insight Row

    // Now supports insight rotation via tap on dot indicator.

    @ViewBuilder
    private func insightRow(_ vm: DashboardViewModel) -> some View {
        let insight = vm.currentInsight
        let insightCount = vm.insights.count

        VStack(spacing: TempoSpacing.xs) {
            Button {
                showInsightDetail = true
            } label: {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: insight.icon)
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoWarning)

                    Text(insight.text)
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .id(insight.text)
                        .transition(.push(from: .trailing))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.tempoCaption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .padding(TempoSpacing.cardPadding)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            }
            .sheet(isPresented: $showInsightDetail) {
                InsightDetailSheet(vm: vm)
            }

            // Insight rotation indicator (if multiple insights)
            if insightCount > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        vm.nextInsight()
                    }
                } label: {
                    HStack(spacing: 4) {
                        ForEach(0 ..< min(insightCount, 6), id: \.self) { index in
                            Circle()
                                .fill(index == (vm.insights.firstIndex(where: { $0.text == insight.text }) ?? 0)
                                    ? Color.tempoSignal : Color.tempoTextTertiary.opacity(0.4))
                                .frame(width: 5, height: 5)
                        }
                        if insightCount > 6 {
                            Text("+\(insightCount - 6)")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Score Trend Sparkline

    @ViewBuilder
    private func scoreTrendSparkline(_ vm: DashboardViewModel) -> some View {
        if vm.scoreTrend.count >= 2 {
            HStack(spacing: TempoSpacing.sm) {
                Text("7-DAY")
                    .font(.tempoModuleTag)
                    .fontWeight(.bold)
                    .tracking(0.8)
                    .foregroundStyle(Color.tempoTextTertiary)

                SparklineView(
                    data: vm.scoreTrend.map { Double($0.score) },
                    lineColor: sparklineColor(vm.scoreTrend),
                    height: 24
                )

                if let last = vm.scoreTrend.last, let prev = vm.scoreTrend.dropLast().last {
                    let delta = last.score - prev.score
                    let trend = vm.scoreTrendDirection
                    HStack(spacing: 2) {
                        Image(systemName: trend.icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(trend.color)
                        Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                            .font(.tempoDataSmall)
                            .fontWeight(.semibold)
                            .foregroundStyle(delta >= 0 ? Color.tempoSuccess : Color.tempoError)
                            .contentTransition(.numericText(countsDown: delta < 0))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
    }

    private func sparklineColor(_ trend: [DashboardViewModel.DailyScorePoint]) -> Color {
        guard let first = trend.first, let last = trend.last else {
            return .tempoTextSecondary
        }
        if last.score > first.score {
            return Color.tempoSuccess
        }
        if last.score < first.score {
            return Color.tempoError
        }
        return Color.tempoTextSecondary
    }

    // MARK: - Card Shell

    @Environment(\.colorScheme)
    private var colorScheme

    private func cardShell(
        label: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.tempoModuleTag)
                .fontWeight(.bold)
                .tracking(1.2)
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.bottom, TempoSpacing.sm)

            content()

            Spacer(minLength: 0)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoBorder.opacity(colorScheme == .dark ? 0.4 : 0), lineWidth: 0.5)
        )
    }

    // MARK: - Reusable Components

    private func connectPrompt(icon: String, message: String, buttonText: String = "Connect", action: @escaping () -> Void) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Spacer(minLength: 0)

            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.tempoTextTertiary)

            Text(message)
                .font(.tempoCaption1)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Button(action: action) {
                Text(buttonText)
                    .font(.tempoCaption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextInverse)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.tempoSignal)
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func miniMetric(label: String, value: String, valueColor: Color = .tempoTextPrimary) -> some View {
        HStack {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Spacer()
            Text(value)
                .font(.tempoDataSmall)
                .fontWeight(.bold)
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
        }
    }

    /// Mini metric with numeric text animation for count-up effect.
    private func miniMetricAnimated(label: String, value: String, valueColor: Color = .tempoTextPrimary) -> some View {
        HStack {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Spacer()
            Text(value)
                .font(.tempoDataSmall)
                .fontWeight(.bold)
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
        }
    }

    private func progressBar(progress: Double, color: Color, height: CGFloat = 3) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.tempoBorder.opacity(0.5))
                    .frame(height: height)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(progress, 1.0), height: height)
            }
        }
        .frame(height: height)
    }

    private func macroDot(letter: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(letter) \(value)")
                .font(.tempoModuleTag)
                .fontWeight(.medium)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    private func strainIndicator(_ strain: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.tempoBorder.opacity(0.5))
                        .frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.tempoSuccess, Color.tempoWarning, Color.tempoError],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(strain / 21.0, 1.0), height: 3)
                }
            }
            .frame(height: 3)

            Text("Strain \(String(format: "%.1f", strain))")
                .font(.tempoModuleTag)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Helpers

    private func examCountdownColor(_ daysUntil: Int) -> Color {
        switch daysUntil {
        case ...3: Color.tempoError
        case 4 ... 7: Color.tempoWarning
        default: Color.tempoTextSecondary
        }
    }

    private func stepsColor(_ steps: Int?, target: Int) -> Color {
        guard let steps else {
            return .tempoTextSecondary
        }
        if steps >= target {
            return .tempoSuccess
        }
        if steps >= Int(Double(target) * 0.7) {
            return .tempoTextPrimary
        }
        return .tempoTextSecondary
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return LayoutResult(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}

// MARK: - Recovery Zone Color

extension RecoveryZone {
    var color: Color {
        switch self {
        case .green: Color.tempoRecoveryGreen
        case .yellow: Color.tempoRecoveryYellow
        case .red: Color.tempoRecoveryRed
        }
    }
}

// MARK: - InsightDetailSheet

private struct InsightDetailSheet: View {
    let vm: DashboardViewModel
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        let insight = vm.currentInsight
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                    // Insight header
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: insight.icon)
                            .font(.tempoTitle1)
                            .foregroundStyle(Color.tempoWarning)
                        Text(insight.detailTitle)
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .padding(.top, TempoSpacing.md)

                    // Main finding
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("FINDING")
                            .font(.tempoModuleTag)
                            .fontWeight(.bold)
                            .tracking(1.2)
                            .foregroundStyle(Color.tempoTextTertiary)

                        Text(insight.detailFinding)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .padding(TempoSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                    // Recommendation
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("RECOMMENDATION")
                            .font(.tempoModuleTag)
                            .fontWeight(.bold)
                            .tracking(1.2)
                            .foregroundStyle(Color.tempoTextTertiary)

                        HStack(alignment: .top, spacing: TempoSpacing.sm) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.tempoCallout)
                                .foregroundStyle(Color.tempoSignal)
                                .frame(width: 24)

                            Text(insight.detailRecommendation)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                        }
                    }
                    .padding(TempoSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                    // Current status snapshot
                    VStack(alignment: .leading, spacing: TempoSpacing.md) {
                        Text("CURRENT STATUS")
                            .font(.tempoModuleTag)
                            .fontWeight(.bold)
                            .tracking(1.2)
                            .foregroundStyle(Color.tempoTextTertiary)

                        insightMetricRow(
                            icon: "heart.fill",
                            label: "Recovery",
                            value: vm.body.formattedRecovery,
                            color: vm.body.recoveryZone?.color ?? .tempoTextTertiary
                        )

                        insightMetricRow(
                            icon: "moon.fill",
                            label: "Sleep",
                            value: vm.body.formattedSleep,
                            color: sleepColor(vm.body.sleepHours)
                        )

                        insightMetricRow(
                            icon: "book.fill",
                            label: "Study Streak",
                            value: "\(vm.mind.currentStreakDays) days",
                            color: vm.mind.currentStreakDays >= 7 ? .tempoAmber : .tempoTextPrimary
                        )

                        insightMetricRow(
                            icon: "figure.run",
                            label: "Training",
                            value: trainingStatusText(vm.move),
                            color: trainingStatusColor(vm.move)
                        )
                    }
                    .padding(TempoSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.xxxxl)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
        }
    }

    private func insightMetricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.tempoSubheadline)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Text(value)
                .font(.tempoDataMedium)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    private func sleepColor(_ hours: Double?) -> Color {
        guard let hours else {
            return .tempoTextTertiary
        }
        if hours >= 7 {
            return .tempoSuccess
        }
        if hours >= 6 {
            return .tempoWarning
        }
        return .tempoError
    }

    private func trainingStatusText(_ move: MoveQuadrantData) -> String {
        switch move.workoutStatus {
        case .completed: "Done"
        case .planned: "Planned"
        case .restDay: "Rest Day"
        case .none: "No workout"
        }
    }

    private func trainingStatusColor(_ move: MoveQuadrantData) -> Color {
        switch move.workoutStatus {
        case .completed: .tempoSuccess
        case .planned: .tempoAmber
        case .restDay: .tempoTextSecondary
        case .none: .tempoTextTertiary
        }
    }
}

// MARK: - ScoreBreakdownSheet

private struct ScoreBreakdownSheet: View {
    let vm: DashboardViewModel
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        let breakdown = vm.scoreBreakdown
        NavigationStack {
            VStack(spacing: TempoSpacing.xl) {
                // Total score hero
                if let score = vm.dailyScore {
                    VStack(spacing: TempoSpacing.xs) {
                        ScoreRingView(
                            score: Double(score),
                            maxScore: 100,
                            size: 80,
                            strokeWidth: 8
                        )
                        Text("\(score)/100")
                            .font(.tempoDataLarge)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text("Daily Score")
                            .font(.tempoFootnote)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .padding(.top, TempoSpacing.lg)
                }

                // Component breakdown
                VStack(spacing: TempoSpacing.md) {
                    scoreComponentRow(
                        icon: "heart.fill",
                        label: "Recovery",
                        points: breakdown.recoveryPoints,
                        maxPoints: 25,
                        isAvailable: breakdown.recoveryAvailable,
                        color: .tempoRecoveryGreen
                    )
                    scoreComponentRow(
                        icon: "fork.knife",
                        label: "Nutrition",
                        points: breakdown.nutritionPoints,
                        maxPoints: 25,
                        isAvailable: breakdown.nutritionAvailable,
                        color: .tempoViolet
                    )
                    scoreComponentRow(
                        icon: "book.fill",
                        label: "Study",
                        points: breakdown.studyPoints,
                        maxPoints: 25,
                        isAvailable: breakdown.studyAvailable,
                        color: .tempoElectric
                    )
                    scoreComponentRow(
                        icon: "figure.run",
                        label: "Movement",
                        points: breakdown.movementPoints,
                        maxPoints: 25,
                        isAvailable: breakdown.movementAvailable,
                        color: .tempoAmber
                    )
                }
                .padding(TempoSpacing.cardPadding)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                Spacer()
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Score Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func scoreComponentRow(
        icon: String, label: String, points: Double,
        maxPoints: Double, isAvailable: Bool, color: Color
    ) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            HStack {
                Image(systemName: icon)
                    .font(.tempoSubheadline)
                    .foregroundStyle(isAvailable ? color : Color.tempoTextTertiary)
                    .frame(width: 20)

                Text(label)
                    .font(.tempoSubheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isAvailable ? Color.tempoTextPrimary : Color.tempoTextTertiary)

                Spacer()

                if isAvailable {
                    Text("\(String(format: "%.1f", points))/\(Int(maxPoints))")
                        .font(.tempoDataMedium)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.tempoTextPrimary)
                } else {
                    Text("--")
                        .font(.tempoDataMedium)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.tempoBorder.opacity(0.5))
                        .frame(height: 6)
                    if isAvailable {
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * min(points / maxPoints, 1.0), height: 6)
                    }
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - SparklineView

private struct SparklineView: View {
    let data: [Double]
    let lineColor: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 100
                let range = max(maxVal - minVal, 1)

                Path { path in
                    for (index, value) in data.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(data.count - 1)
                        let y = geo.size.height * (1 - CGFloat((value - minVal) / range))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .environment(ServiceContainer.mock())
}
