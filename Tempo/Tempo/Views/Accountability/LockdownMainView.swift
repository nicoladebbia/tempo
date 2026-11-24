//
// LockdownMainView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - LockdownMainView

// Per BUILD_PLAN step 10.3.
// Per MODULE_ACCOUNTABILITY.md — Lockdown Main View.
// Per WIREFRAMES.md Section 4 — Screen 65.
// Per UX_COPY_BIBLE.md Section 5 — Accountability strings.

struct LockdownMainView: View {
    @Bindable
    var viewModel: AccountabilityViewModel
    @Binding
    var showFocusTimer: Bool
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.tideMood)
    private var mood
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    private var focusTimerEnabled: Bool {
        settings?.focusTimerEnabled ?? false
    }

    @State
    private var showUnlockCelebration = false
    /// The pending auto-dismiss of the unlock moment, so Continue (or a second unlock) can cancel it.
    @State
    private var unlockDismissTask: Task<Void, Never>?

    @State
    private var showNonNegotiableSetup = false
    @State
    private var expandedCardID: PersistentIdentifier?
    @State
    private var showMealLogging = false
    @State
    private var showHistoryAlert = false
    @State
    private var editingNonNegotiable: NonNegotiableProgress?

    private var showsQuickAction: Bool {
        hasTimedNonNegotiable && focusTimerEnabled
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main scrollable content
            TideScrollPage(energy: 1, spacing: Tide.s4, spacer: Tide.s2) {
                // Date display
                dateHeader

                if viewModel.isLoading, viewModel.progressItems.isEmpty {
                    // The page's own shape, shimmering, instead of a false "Locked, 0 done".
                    loadingState
                } else if viewModel.progressItems.isEmpty {
                    // Nothing to be done yet: the orders and the one way forward,
                    // with no dial counting 0 of 0.
                    drillSergeantSection
                    emptyState
                } else {
                    // The day in one read: the dial, whether it is on pace, the orders...
                    statusBanner
                    progressPredictionSection
                    drillSergeantSection

                    // ...then what is still open, with what is finished under it.
                    nonNegotiableCards
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // The one primary action, under the thumb. It is the same at every
                // text size; the scrim keeps the cards from reading through it.
                pinnedAction
            }
            .refreshable {
                viewModel.loadToday(modelContext: modelContext)
                // Re-evaluate smart notifications now that progress is fresh.
                if let notifService = services.notifications as? NotificationService {
                    viewModel.scheduleSmartNotifications(
                        notificationService: notifService,
                        modelContext: modelContext
                    )
                }
            }

            // Unlock celebration overlay
            if showUnlockCelebration {
                unlockCelebrationOverlay
            }
        }
        .tidePage(energy: 1)
        // The unlock is a moment of its own: the bar steps aside while it plays.
        .toolbar(showUnlockCelebration ? .hidden : .automatic, for: .navigationBar)
        // The field rests while a sheet is over this page.
        .tideCovered(showNonNegotiableSetup || showMealLogging || editingNonNegotiable != nil)
        .sheet(isPresented: $showNonNegotiableSetup) {
            NonNegotiableSetupView()
                .onDisappear {
                    viewModel.loadToday(modelContext: modelContext)
                }
        }
        .onChange(of: viewModel.isLeisureUnlocked) { _, unlocked in
            if unlocked {
                withAnimation(Tide.lively) {
                    showUnlockCelebration = true
                }
                // Dismiss after 6 seconds: the burst plays for 4.5, then Continue is the way out.
                unlockDismissTask?.cancel()
                unlockDismissTask = Task {
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else {
                        return
                    }
                    withAnimation { showUnlockCelebration = false }
                }
            }
        }
        .sheet(isPresented: $showMealLogging) {
            MealLoggingView()
                .onDisappear {
                    viewModel.loadToday(modelContext: modelContext)
                }
        }
        .alert("History", isPresented: $showHistoryAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("History view coming soon")
        }
        .sheet(item: $editingNonNegotiable) { _ in
            NonNegotiableSetupView()
                .onDisappear {
                    viewModel.loadToday(modelContext: modelContext)
                }
        }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                .tideLabel()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status Banner

    // Per MODULE_ACCOUNTABILITY.md — the day's progress as a shader-lit dial.

    private var statusBanner: some View {
        let percent = Int((min(max(viewModel.completionPercentage, 0), 1) * 100).rounded())

        return RecoveryHero {
            TideDial(score: percent, caption: "Done", diameter: Tide.dialHero)
        } side: {
            HStack(spacing: Tide.s2) {
                Image(systemName: heroIcon)
                    .font(Tide.title2)
                    .foregroundStyle(lockColor)
                    .symbolEffect(.bounce, value: viewModel.isLeisureUnlocked)
                    .accessibilityHidden(true)

                Text(heroTitle)
                    .font(Tide.title2)
                    .foregroundStyle(lockColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(statusTimeContext)
                .font(Tide.body)
                .foregroundStyle(statusTimeColor)
                .fixedSize(horizontal: false, vertical: true)

            TideNumber(
                "\(viewModel.completedCount)",
                unit: "of \(viewModel.totalCount) done",
                size: Tide.numeralM,
                relativeTo: .title
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(heroTitle). \(viewModel.completedCount) of \(viewModel.totalCount) done. \(statusTimeContext)"
        )
    }

    /// A rest day says so; the lock only speaks for a normal day.
    private var heroTitle: String {
        if let override = viewModel.activeOverride {
            return Self.overrideTitle(override)
        }
        return viewModel.isLeisureUnlocked ? "Unlocked" : "Locked"
    }

    private var heroIcon: String {
        if viewModel.activeOverride != nil {
            return "bed.double.fill"
        }
        return viewModel.isLeisureUnlocked ? "lock.open.fill" : "lock.fill"
    }

    private static func overrideTitle(_ type: AccountabilityOverrideType) -> String {
        switch type {
        case .restDayFull: "Full rest day"
        case .restDayReduced: "Reduced rest day"
        case .sickDay: "Sick day"
        case .mentalHealthDay: "Mental health day"
        case .injuryMode: "Injury mode"
        case .vacationMode: "Vacation mode"
        }
    }

    private var lockColor: Color {
        if viewModel.activeOverride != nil {
            return Tide.text
        }
        return viewModel.isLeisureUnlocked ? TideTone.mint : Tide.danger
    }

    /// Per UX_COPY_BIBLE.md — time context strings
    private var statusTimeContext: String {
        if viewModel.activeOverride != nil {
            return "Rest days don't count toward your streak."
        }
        if viewModel.isLeisureUnlocked {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour < 12 {
                return "All done by noon. Legend."
            }
            let early = viewModel.timeToPS5
            if early > 0 {
                return "Unlocked \(viewModel.formattedTimeToPS5) early. Ahead of schedule."
            }
            return "Unlocked. Better late than never."
        }

        if viewModel.dailyState == .dayFailed {
            return "PS5 time passed. Handle your business."
        }

        let remaining = viewModel.totalCount - viewModel.completedCount
        if remaining == 1 {
            return "Just 1 more. So close."
        }

        let timeToPS5 = viewModel.timeToPS5
        if timeToPS5 < 30 * 60 {
            return "\(viewModel.formattedTimeToPS5). Move."
        }
        if timeToPS5 < 60 * 60 {
            return "\(viewModel.formattedTimeToPS5). Clock's ticking."
        }
        if timeToPS5 < 2 * 3600 {
            return "\(viewModel.formattedTimeToPS5) left. Focus up."
        }
        return "\(viewModel.formattedTimeToPS5) until your usual PS5 time"
    }

    private var statusTimeColor: Color {
        if viewModel.activeOverride != nil {
            return Tide.text2
        }
        if viewModel.isLeisureUnlocked {
            return TideTone.mint
        }
        if viewModel.dailyState == .dayFailed {
            return Tide.danger
        }
        if viewModel.timeToPS5 < 30 * 60 {
            return Tide.danger
        }
        return Tide.text2
    }

    // MARK: - Drill Sergeant

    // Per MODULE_ACCOUNTABILITY.md — contextual drill sergeant message.
    // Enhanced with dynamic, context-aware message generation.

    private var drillSergeantSection: some View {
        // Rooted in a stack so the card's own lifecycle is never attached to an EmptyView.
        VStack(spacing: 0) {
            if let result = drillSergeantResult {
                TideOrdersCard(message: result.message, intensity: result.intensity)
            }
        }
    }

    private var drillSergeantResult: (message: String, intensity: DrillSergeantIntensity)? {
        let studyProgress = viewModel.progressItems.first(where: {
            $0.nonNegotiable?.type == .study
        })
        let context = DrillSergeantContext(
            completedCount: viewModel.completedCount,
            totalCount: viewModel.totalCount,
            streakCount: viewModel.streakCount,
            timeToPS5: viewModel.timeToPS5,
            totalStudyMinutes: viewModel.totalFocusMinutesToday,
            studyTargetMinutes: Int(studyProgress?.targetValue ?? 120),
            recoveryScore: nil, // Will be wired when RecoveryViewModel is connected
            dailyState: viewModel.dailyState,
            isWeekend: Calendar.current.isDateInWeekend(Date()),
            hourOfDay: Calendar.current.component(.hour, from: Date())
        )
        return DrillSergeantMessageGenerator.generate(context: context)
    }

    // MARK: - Progress Prediction

    // Predicts whether user will complete all non-negotiables by PS5 time.

    private var progressPredictionSection: some View {
        VStack(spacing: 0) {
            if let prediction = completionPrediction, !viewModel.isLeisureUnlocked {
                let tint = prediction.onTrack ? TideTone.mint : Tide.danger
                // A pace read-out under the dial, not a card of its own.
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Image(systemName: prediction.onTrack ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)

                    Text(prediction.message)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var completionPrediction: (message: String, onTrack: Bool)? {
        guard viewModel.totalCount > 0,
              viewModel.dailyState != .unlocked,
              viewModel.dailyState != .morningSetup,
              viewModel.dailyState != .overrideActive,
              viewModel.dailyState != .review
        else {
            return nil
        }

        let done = viewModel.completedCount
        let total = viewModel.totalCount
        let remaining = total - done
        let timeToPS5 = viewModel.timeToPS5

        // Already failed
        if viewModel.dailyState == .dayFailed {
            return ("PS5 time has passed. \(remaining) task\(remaining == 1 ? "" : "s") still incomplete.", false)
        }

        // All done (shouldn't reach here since we filter .unlocked)
        if remaining == 0 {
            return nil
        }

        // Calculate pace: how much time has elapsed and how much is done
        let totalDaySeconds: TimeInterval = 11.5 * 3600 // 8 AM to 7:30 PM typical
        let elapsed = max(1, totalDaySeconds - timeToPS5)
        let pacePerTask = done > 0 ? elapsed / Double(done) : totalDaySeconds / Double(total)
        let estimatedTimeForRemaining = pacePerTask * Double(remaining)

        // Study-specific prediction
        let studyProgress = viewModel.progressItems.first(where: { $0.nonNegotiable?.type == .study })
        let studyRemaining = max(0, (studyProgress?.targetValue ?? 0) - (studyProgress?.currentValue ?? 0))

        if studyRemaining > 0 {
            let studySecondsNeeded = studyRemaining * 60 // minutes to seconds
            let totalTimeNeeded = max(estimatedTimeForRemaining, studySecondsNeeded)

            if totalTimeNeeded > timeToPS5 {
                let deficit = Int((totalTimeNeeded - timeToPS5) / 60)
                return ("At this pace, you'll be \(deficit)min behind. Pick up the speed.", false)
            }
        }

        if estimatedTimeForRemaining > timeToPS5 {
            return ("WARNING: At current pace, you won't finish in time. Accelerate.", false)
        }

        // Estimate finish time
        let estimatedFinish = Date().addingTimeInterval(estimatedTimeForRemaining)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let finishStr = formatter.string(from: estimatedFinish)

        if estimatedTimeForRemaining < timeToPS5 * 0.5 {
            return ("On pace to finish by \(finishStr). Ahead of schedule.", true)
        }

        return ("At this pace, you'll finish by \(finishStr). Stay focused.", true)
    }

    // MARK: - Non-Negotiable Cards

    /// What is still open comes first, so the next thing to do is never below the fold.
    private var openItems: [NonNegotiableProgress] {
        viewModel.progressItems.filter { !$0.isCompleted }
    }

    /// Done and skipped, in the order they were set up.
    private var finishedItems: [NonNegotiableProgress] {
        viewModel.progressItems.filter(\.isCompleted)
    }

    private var nonNegotiableCards: some View {
        let open = openItems
        let finished = finishedItems
        return VStack(spacing: Tide.s4) {
            if !open.isEmpty {
                TideSectionLabel(title: "To do", trailing: "\(open.count) left")
                    .padding(.top, Tide.s2)
                ForEach(open, id: \.persistentModelID) { progress in
                    card(for: progress)
                }
            }
            if !finished.isEmpty {
                TideSectionLabel(title: "Done", trailing: "\(finished.count) of \(viewModel.progressItems.count)")
                    .padding(.top, open.isEmpty ? Tide.s2 : Tide.s1)
                ForEach(finished, id: \.persistentModelID) { progress in
                    card(for: progress)
                }
            }
        }
        // A finished task slides down to the Done group instead of jumping.
        .animation(Tide.snap, value: finished.count)
    }

    private func card(for progress: NonNegotiableProgress) -> some View {
        NonNegotiableCardView(
            progress: progress,
            isExpanded: expandedCardID == progress.persistentModelID,
            habitStreakCount: viewModel.habitStreakCount(for: progress.nonNegotiable?.type ?? .custom),
            onTap: {
                withAnimation(Tide.snap) {
                    expandedCardID = expandedCardID == progress.persistentModelID
                        ? nil
                        : progress.persistentModelID
                }
            },
            onComplete: {
                viewModel.completeItem(progress, modelContext: modelContext)
            },
            onSkip: {
                viewModel.skipItem(progress, modelContext: modelContext)
            },
            onUpdateValue: { value in
                viewModel.updateItemProgress(progress, value: value, modelContext: modelContext)
            },
            onStartTimer: focusTimerEnabled ? {
                viewModel.configureFocusTimer()
                showFocusTimer = true
            } : nil,
            onLogMeal: {
                showMealLogging = true
            },
            onEditNonNegotiable: {
                editingNonNegotiable = progress
            },
            onViewHistory: {
                showHistoryAlert = true
            },
            secondaryActions: showsQuickAction
        )
    }

    // MARK: - Empty State

    // Per MODULE_ACCOUNTABILITY.md — empty state when no non-negotiables.
    // The way forward is the pinned button; this is the explanation above it.

    private var emptyState: some View {
        TideEmptyPanel(
            systemImage: "lock.fill",
            title: "No non-negotiables set",
            message: "Define what you MUST do each day before you earn your downtime."
        )
        .tideCard()
    }

    // MARK: - Loading State

    /// The shape of the page while the day loads: the dial and its lines, then three cards.
    private var loadingState: some View {
        VStack(spacing: Tide.s4) {
            HStack(spacing: Tide.s5) {
                Circle()
                    .fill(Tide.fill)
                    .frame(width: Tide.dialHero, height: Tide.dialHero)
                    .shimmer()
                VStack(alignment: .leading, spacing: Tide.s3) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: Tide.s1, style: .continuous)
                            .fill(Tide.fill)
                            .frame(height: index == 0 ? Tide.s6 : Tide.s4)
                            .frame(maxWidth: index == 2 ? Tide.s10 * 2 : .infinity)
                            .shimmer()
                    }
                }
            }
            .padding(.vertical, Tide.s2)

            ForEach(0 ..< 3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .fill(Tide.fill)
                    .frame(height: Tide.s10 * 2.5)
                    .shimmer()
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Quick Action Button

    // Per MODULE_ACCOUNTABILITY.md — sticky study timer CTA.

    private var hasTimedNonNegotiable: Bool {
        viewModel.progressItems.contains(where: { p in
            p.nonNegotiable?.trackingMethod == .timer
        })
    }

    private var studyComplete: Bool {
        viewModel.progressItems.allSatisfy { p in
            guard p.nonNegotiable?.type == .study else {
                return true
            }
            return p.isCompleted
        }
    }

    private var quickActionLabel: some View {
        HStack(spacing: Tide.s2) {
            Image(systemName: "play.fill")
                .accessibilityHidden(true)
            Text(studyComplete ? "Start another session" : "Start study timer")
        }
        .frame(maxWidth: .infinity)
    }

    private func startFocusTimer() {
        HapticManager.impact(.heavy)
        viewModel.configureFocusTimer()
        showFocusTimer = true
    }

    @ViewBuilder
    private var quickActionButton: some View {
        if studyComplete {
            Button(action: startFocusTimer) { quickActionLabel }
                .buttonStyle(.tideGlass)
        } else {
            Button(action: startFocusTimer) { quickActionLabel }
                .buttonStyle(.tidePrimary)
        }
    }

    // MARK: - Pinned Action

    // The page's one primary action, pinned above the tab bar: the study timer
    // on a day with tasks, "Set up" on a day without any.

    @ViewBuilder
    private var pinnedAction: some View {
        if viewModel.progressItems.isEmpty, !viewModel.isLoading {
            pinnedBar {
                Button("Set up non-negotiables") {
                    showNonNegotiableSetup = true
                }
                .buttonStyle(.tidePrimary)
            }
        } else if showsQuickAction, !viewModel.progressItems.isEmpty {
            pinnedBar { quickActionButton }
        }
    }

    private func pinnedBar(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s2)
            .lockdownPinnedScrim()
    }

    // MARK: - Unlock Celebration

    // Per MODULE_ACCOUNTABILITY.md - burst + glow on leisure unlock.
    // Per SOUND_AND_HAPTICS.md - success haptic as the lock opens.
    // The moment itself lives in the Lockdown kit; this only feeds it the day's numbers.

    private var unlockCelebrationOverlay: some View {
        let score = viewModel.accountability.map {
            services.accountabilityEngine.calculateDailyScore(accountability: $0)
        }

        return LockdownUnlockMoment(score: score, streak: viewModel.streakCount) {
            unlockDismissTask?.cancel()
            withAnimation { showUnlockCelebration = false }
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}

// MARK: - NonNegotiableCardView

// Per MODULE_ACCOUNTABILITY.md — Individual card for each non-negotiable.
// Per WIREFRAMES.md Section 4 — Card states: notStarted, inProgress, completed, overdue, skipped.

struct NonNegotiableCardView: View {
    let progress: NonNegotiableProgress
    let isExpanded: Bool
    var habitStreakCount: Int = 0
    let onTap: () -> Void
    let onComplete: () -> Void
    let onSkip: () -> Void
    let onUpdateValue: (Double) -> Void
    var onStartTimer: (() -> Void)?
    var onLogMeal: () -> Void = {}
    var onEditNonNegotiable: () -> Void = {}
    var onViewHistory: () -> Void = {}
    /// True when the page already carries one primary action (the pinned timer
    /// button): the row actions step back to glass so only one button leads.
    var secondaryActions = false

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var nn: NonNegotiable? {
        progress.nonNegotiable
    }

    private var cardState: CardState {
        resolveCardState()
    }

    private var fraction: Double {
        progress.targetValue > 0 ? min(1, progress.currentValue / progress.targetValue) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            // Row 1: Icon + Name + Status
            headerRow

            if !isFinished {
                // Row 2: Progress bar
                progressRow

                // Row 3: Supporting text + Action
                supportingRow
            }

            // Expanded detail (a finished row has nothing left to do)
            if isExpanded, !progress.isCompleted {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tideCard(padding: isFinished ? Tide.s3 : Tide.s4, radius: Tide.tileRadius)
        .overlay(cardBorder)
        .opacity(cardState == .skipped ? 0.6 : 1.0)
        .contentShape(.rect(cornerRadius: Tide.tileRadius))
        .onTapGesture { onTap() }
        .contextMenu { cardContextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(progress.isCompleted ? "" : (isExpanded ? "Hides actions" : "Shows actions"))
    }

    // MARK: - Header Row

    private var headerRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))

        return layout {
            // Icon
            TideAreaIconTile(systemName: nn?.icon ?? "star.fill", tint: iconColor)

            VStack(alignment: .leading, spacing: Tide.hair) {
                HStack(spacing: Tide.s2) {
                    // Name
                    Text(nn?.name ?? "Task")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .strikethrough(cardState == .skipped)

                    // Mini streak badge
                    if habitStreakCount > 0 {
                        HStack(spacing: Tide.hair) {
                            Image(systemName: "flame.fill")
                                .font(Tide.label)
                                .accessibilityHidden(true)
                            Text("\(habitStreakCount)")
                                .font(Tide.numeral(Tide.numeralS - Tide.s2, .bold))
                        }
                        .foregroundStyle(Tide.streak)
                    }
                }

                // Source badge; a finished row says how it ended instead.
                if isFinished {
                    Text(finishedText)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    sourceBadge
                }
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }

            // Status indicator (a finished row keeps its one action beside the check)
            if isFinished {
                HStack(spacing: Tide.s2) {
                    actionButton
                    statusIndicator
                }
            } else {
                statusIndicator
            }
        }
    }

    /// Done and skipped rows are one line: what is open is what gets the room.
    private var isFinished: Bool {
        cardState == .completed || cardState == .skipped
    }

    private var finishedText: String {
        cardState == .skipped ? "Skipped today" : supportingText
    }

    private var iconColor: Color {
        switch cardState {
        case .notStarted: Tide.text3
        case .inProgress: mood.accent
        case .completed: TideTone.mint
        case .overdue: Tide.danger
        case .skipped: Tide.text3
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch cardState {
        case .notStarted:
            Text("Not started").tideLabel(Tide.text3)
        case .inProgress:
            Text(progressText)
                .font(Tide.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(Tide.text2)
        case .completed:
            // The "Done" section says the word; the row keeps just the tick.
            Image(systemName: "checkmark.circle.fill")
                .font(Tide.title2)
                .foregroundStyle(TideTone.mint)
                .accessibilityHidden(true)
        case .overdue:
            Text("Overdue").tideLabel(Tide.danger)
        case .skipped:
            Image(systemName: "forward.circle.fill")
                .font(Tide.title2)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
    }

    private var progressText: String {
        guard let nn else {
            return ""
        }
        switch nn.trackingMethod {
        case .timer:
            let current = Int(progress.currentValue)
            let target = Int(progress.targetValue)
            let currentH = current / 60
            let currentM = current % 60
            let targetH = target / 60
            let targetM = target % 60
            if targetH > 0 {
                return "\(currentH)h \(currentM)m / \(targetH)h \(targetM)m"
            }
            return "\(currentM)m / \(targetM)m"
        case .manual:
            return "\(Int(progress.currentValue)) / \(Int(progress.targetValue))"
        case .autoWhoop,
             .autoHealthkit:
            return "\(Int(progress.currentValue)) / \(Int(progress.targetValue))"
        }
    }

    // MARK: - Progress Row

    private var progressRow: some View {
        HStack(spacing: Tide.s3) {
            // Progress bar
            TideLevelBar(
                progress: fraction,
                color: progressBarColor,
                height: Tide.bar
            )

            // Percentage
            Text("\(Int(fraction * 100))%")
                .font(Tide.numeral(Tide.numeralS - Tide.s1, .semibold))
                .foregroundStyle(Tide.text2)
                .frame(minWidth: Tide.s10, alignment: .trailing)
        }
    }

    private var progressBarColor: Color {
        let pct = progress.targetValue > 0 ? progress.currentValue / progress.targetValue : 0
        if pct >= 0.8 {
            return TideTone.mint
        }
        if pct >= 0.5 {
            return TideTone.amber
        }
        return mood.accent
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let nn {
            let badgeText = switch nn.type {
            case .train: "Whoop"
            case .meals: "NutriTrack"
            case .study: "Manual"
            case .sleep: "HealthKit"
            case .steps: "HealthKit"
            case .hydration: "Manual"
            case .custom: "Manual"
            }

            Text(badgeText).tideLabel(Tide.text3)
        }
    }

    // MARK: - Supporting Row

    private var supportingRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))

        return layout {
            Text(supportingText)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }

            // Action button
            actionButton
        }
    }

    private var supportingText: String {
        guard let nn else {
            return ""
        }
        switch nn.type {
        case .study:
            if !progress.isCompleted, progress.currentValue == 0 {
                return "Start a focus session to begin tracking"
            }
            if progress.isCompleted {
                return "\(Int(progress.currentValue))m total"
            }
            return "In progress"
        case .train:
            if !progress.isCompleted {
                return "Waiting for Whoop sync..."
            }
            return "Training recorded"
        case .meals:
            let logged = Int(progress.currentValue)
            let total = Int(progress.targetValue)
            if logged == 0 {
                return "Next: Breakfast"
            }
            if logged == 1 {
                return "Next: Lunch"
            }
            if logged < total {
                return "Next: Dinner before 8pm"
            }
            return "All meals logged today"
        case .sleep:
            if !progress.isCompleted {
                return "Syncs from HealthKit"
            }
            return "Sleep tracked"
        case .steps:
            if !progress.isCompleted {
                return "Syncs from HealthKit"
            }
            return "Steps goal met"
        case .hydration:
            if !progress.isCompleted, progress.currentValue == 0 {
                return "Tap to log water intake"
            }
            if progress.isCompleted {
                return "Hydration goal met"
            }
            return "In progress"
        case .custom:
            if !progress.isCompleted, progress.currentValue == 0 {
                return "Tap to start tracking"
            }
            if progress.isCompleted {
                return "Completed"
            }
            return "In progress"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let nn {
            switch nn.type {
            case .study:
                if let onStartTimer {
                    if progress.isCompleted {
                        pillButton(title: "Add more", style: .outline) { onStartTimer() }
                    } else {
                        pillButton(title: "Start timer", style: .filled) { onStartTimer() }
                    }
                }
            case .train:
                if !progress.isCompleted {
                    pillButton(title: "Log manually", style: .filled) {
                        onComplete()
                    }
                }
            case .meals:
                if !progress.isCompleted {
                    pillButton(title: "Log meal", style: .filled) { onLogMeal() }
                }
            case .sleep,
                 .steps:
                // Auto-tracked from HealthKit — no manual action
                EmptyView()
            case .hydration:
                if !progress.isCompleted {
                    pillButton(title: "+", style: .filled) {
                        onUpdateValue(progress.currentValue + 1)
                    }
                    .accessibilityLabel("Add one")
                }
            case .custom:
                switch nn.trackingMethod {
                case .timer:
                    if let onStartTimer, !progress.isCompleted {
                        pillButton(title: "Start timer", style: .filled) { onStartTimer() }
                    }
                case .manual:
                    if !progress.isCompleted {
                        pillButton(title: "+", style: .filled) {
                            onUpdateValue(progress.currentValue + 1)
                        }
                        .accessibilityLabel("Add one")
                    }
                case .autoWhoop,
                     .autoHealthkit:
                    EmptyView()
                }
            }
        }
    }

    enum PillStyle { case filled, outline }

    private func pillButton(title: String, style requested: PillStyle, action: @escaping () -> Void) -> some View {
        let style: PillStyle = secondaryActions ? .outline : requested
        return Button(action: action) {
            Text(title)
                .font(Tide.bodyStrong)
                .foregroundStyle(style == .filled ? Tide.ink : Tide.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Tide.s4)
                .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                .background {
                    if style == .filled {
                        Capsule().fill(mood.accent)
                    }
                }
                .glassEffect(style == .filled ? .identity : .regular.interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideDivider()

            // Quick actions
            let actions = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                : AnyLayout(HStackLayout(spacing: Tide.s5))
            actions {
                if !progress.isCompleted {
                    Button {
                        HapticManager.notification(.success)
                        onComplete()
                    } label: {
                        Label("Mark complete", systemImage: "checkmark.circle")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(TideTone.mint)
                            .frame(minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    Button {
                        HapticManager.notification(.warning)
                        onSkip()
                    } label: {
                        Label("Skip today", systemImage: "forward.fill")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text3)
                            .frame(minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Card Visual State

    @ViewBuilder
    private var cardBorder: some View {
        if let stateColor = borderColor {
            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                .strokeBorder(stateColor.opacity(cardState == .completed ? 0.3 : 0.55), lineWidth: Tide.rule)
                .allowsHitTesting(false)
        }
    }

    private var borderColor: Color? {
        switch cardState {
        case .notStarted,
             .skipped: nil
        case .inProgress: mood.accent
        case .completed: TideTone.mint
        case .overdue: Tide.danger
        }
    }

    // MARK: - Context Menu

    // Per UX_COPY_BIBLE.md — context menu strings.

    @ViewBuilder
    private var cardContextMenu: some View {
        if !progress.isCompleted {
            Button {
                HapticManager.notification(.success)
                onComplete()
            } label: {
                Label("Mark as Complete", systemImage: "checkmark.circle")
            }

            Button {
                HapticManager.notification(.warning)
                onSkip()
            } label: {
                Label("Skip Today", systemImage: "forward.fill")
            }
        }

        Button {
            onEditNonNegotiable()
        } label: {
            Label("Edit Non-Negotiable", systemImage: "pencil")
        }

        Button {
            onViewHistory()
        } label: {
            Label("View History", systemImage: "clock.arrow.circlepath")
        }
    }

    // MARK: - State Resolution

    enum CardState {
        case notStarted
        case inProgress
        case completed
        case overdue
        case skipped
    }

    private func resolveCardState() -> CardState {
        // Skipped: completed but currentValue < targetValue
        if progress.isCompleted, progress.currentValue < progress.targetValue {
            return .skipped
        }
        if progress.isCompleted {
            return .completed
        }
        if progress.currentValue > 0 {
            return .inProgress
        }
        // Check if overdue (past PS5 time) — use AccountabilityEngine as source of truth
        let now = Date()
        let ps5 = services.accountabilityEngine.ps5Time(for: now)
        if now > ps5, !progress.isCompleted {
            return .overdue
        }
        return .notStarted
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let name = nn?.name ?? "Task"
        let state = cardState
        let pct = progress.targetValue > 0
            ? Int(progress.currentValue / progress.targetValue * 100)
            : 0
        switch state {
        case .notStarted: return "\(name), not started"
        case .inProgress: return "\(name), \(pct) percent complete"
        case .completed: return "\(name), completed"
        case .overdue: return "\(name), overdue"
        case .skipped: return "\(name), skipped"
        }
    }
}
