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

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main scrollable content
            ScrollView {
                VStack(spacing: TempoSpacing.md) {
                    // Date display
                    dateHeader

                    // Status banner
                    statusBanner

                    // Progress prediction
                    progressPredictionSection

                    // Drill sergeant bubble
                    drillSergeantSection

                    // Non-negotiable cards
                    if viewModel.isLoading, viewModel.progressItems.isEmpty {
                        loadingState
                    } else if viewModel.progressItems.isEmpty {
                        emptyState
                    } else {
                        nonNegotiableCards
                    }

                    // Bottom padding for sticky elements (tab bar + leisure bar clearance)
                    Spacer()
                        .frame(height: TempoSpacing.bottomSafe + 60)
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
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

            // Sticky bottom: Quick action + Leisure status
            VStack(spacing: 0) {
                // Quick action button (only when focus timer is enabled)
                if hasTimedNonNegotiable, focusTimerEnabled {
                    quickActionButton
                        .padding(.horizontal, TempoSpacing.screenEdge)
                        .padding(.bottom, TempoSpacing.md)
                }

                // Leisure status bar
                leisureStatusBar
            }
            .background(
                Color.tempoBgPrimary
                    .opacity(0.95)
                    .background(.ultraThinMaterial)
            )

            // Unlock celebration overlay
            if showUnlockCelebration {
                unlockCelebrationOverlay
            }
        }
        .background(Color.tempoBgPrimary)
        .sheet(isPresented: $showNonNegotiableSetup) {
            NonNegotiableSetupView()
                .onDisappear {
                    viewModel.loadToday(modelContext: modelContext)
                }
        }
        .onChange(of: viewModel.isLeisureUnlocked) { _, unlocked in
            if unlocked {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    showUnlockCelebration = true
                }
                // Dismiss after 3 seconds
                Task {
                    try? await Task.sleep(for: .seconds(3))
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
        Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
            .font(.tempoSubheadline)
            .foregroundStyle(Color.tempoTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, TempoSpacing.sm)
    }

    // MARK: - Status Banner

    // Per MODULE_ACCOUNTABILITY.md — 80pt status banner with progress ring.

    private var statusBanner: some View {
        HStack(spacing: TempoSpacing.md) {
            // Progress ring
            CircularRingView(
                progress: viewModel.completionPercentage,
                color: statusRingColor,
                ringSize: .small,
                valueText: "\(Int(viewModel.completionPercentage * 100))%"
            )

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: viewModel.isLeisureUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(viewModel.isLeisureUnlocked ? Color.tempoSuccess : Color.tempoSignal)
                        .symbolEffect(.bounce, value: viewModel.isLeisureUnlocked)

                    Text(viewModel.isLeisureUnlocked ? "UNLOCKED" : "LOCKED")
                        .font(.tempoCallout)
                        .foregroundStyle(viewModel.isLeisureUnlocked ? Color.tempoSuccess : Color.tempoSignal)
                }

                Text(statusTimeContext)
                    .font(.tempoCaption1)
                    .foregroundStyle(statusTimeColor)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.cardPadding)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 1)
        )
    }

    private var statusRingColor: Color {
        if viewModel.isLeisureUnlocked {
            return .tempoSuccess
        }
        if viewModel.dailyState == .dayFailed {
            return .tempoSignal
        }
        let pct = viewModel.completionPercentage
        if pct >= 0.8 {
            return .tempoSuccess
        }
        if pct >= 0.5 {
            return .tempoAmber
        }
        return .tempoElectric
    }

    /// Per UX_COPY_BIBLE.md — time context strings
    private var statusTimeContext: String {
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
        if viewModel.isLeisureUnlocked {
            return .tempoSuccess
        }
        if viewModel.dailyState == .dayFailed {
            return .tempoSignal
        }
        if viewModel.timeToPS5 < 30 * 60 {
            return .tempoSignal
        }
        return .tempoTextSecondary
    }

    // MARK: - Drill Sergeant

    // Per MODULE_ACCOUNTABILITY.md — contextual drill sergeant message.
    // Enhanced with dynamic, context-aware message generation.

    private var drillSergeantSection: some View {
        Group {
            if let result = drillSergeantResult {
                DrillSergeantBubble(message: result.message, intensity: result.intensity)
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
        Group {
            if let prediction = completionPrediction, !viewModel.isLeisureUnlocked {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: prediction.onTrack ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(prediction.onTrack ? Color.tempoSuccess : Color.tempoSignal)

                    Text(prediction.message)
                        .font(.tempoCaption1)
                        .foregroundStyle(prediction.onTrack ? Color.tempoSuccess : Color.tempoSignal)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(TempoSpacing.md)
                .background(
                    (prediction.onTrack ? Color.tempoSuccess : Color.tempoSignal)
                        .opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                        .stroke(
                            (prediction.onTrack ? Color.tempoSuccess : Color.tempoSignal).opacity(0.3),
                            lineWidth: 1
                        )
                )
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

    private var nonNegotiableCards: some View {
        ForEach(viewModel.progressItems, id: \.persistentModelID) { progress in
            NonNegotiableCardView(
                progress: progress,
                isExpanded: expandedCardID == progress.persistentModelID,
                habitStreakCount: viewModel.habitStreakCount(for: progress.nonNegotiable?.type ?? .custom),
                onTap: {
                    withAnimation(TempoAnimation.springMedium) {
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
                }
            )
        }
    }

    // MARK: - Empty State

    // Per MODULE_ACCOUNTABILITY.md — empty state when no non-negotiables.

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.top, TempoSpacing.xxl)

            Text("No non-negotiables set")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(.top, TempoSpacing.md)

            Text("Define what you MUST do each day before you earn your downtime.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, TempoSpacing.xs)

            Button("SET UP NON-NEGOTIABLES") {
                showNonNegotiableSetup = true
            }
            .buttonStyle(.tempoPrimary)
            .padding(.horizontal, TempoSpacing.xxxl)
            .padding(.top, TempoSpacing.lg)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: TempoSpacing.md) {
            ForEach(0 ..< 3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .fill(Color.tempoSurfaceCard)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                            .stroke(Color.tempoBorder, lineWidth: 1)
                    )
                    .shimmer()
            }
        }
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

    private var quickActionButton: some View {
        Button {
            HapticManager.impact(.heavy)
            viewModel.configureFocusTimer()
            showFocusTimer = true
        } label: {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18))

                Text(studyComplete ? "START ANOTHER SESSION" : "START STUDY TIMER")
                    .font(.tempoCallout)
                    .tracking(1)
            }
            .foregroundStyle(studyComplete ? Color.tempoElectric : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if studyComplete {
                    Color.clear
                } else {
                    LinearGradient(
                        colors: [Color.tempoElectric, Color.tempoElectric.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(
                        studyComplete ? Color.tempoElectric : .clear,
                        lineWidth: studyComplete ? 2 : 0
                    )
            )
            .shadow(
                color: studyComplete ? .clear : Color.tempoElectric.opacity(0.3),
                radius: 6, x: 0, y: 4
            )
        }
    }

    // MARK: - Leisure Status Bar

    // Per MODULE_ACCOUNTABILITY.md — pinned above tab bar.

    private var leisureStatusBar: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Divider()

            HStack(spacing: TempoSpacing.sm) {
                // Lock icon
                Image(systemName: leisureLockIcon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(leisureLockColor)
                    .symbolEffect(.pulse, isActive: viewModel.dailyState == .dayFailed)

                VStack(alignment: .leading, spacing: 2) {
                    Text("LEISURE STATUS")
                        .font(.tempoCaption2)
                        .tracking(1)
                        .foregroundStyle(Color.tempoTextTertiary)

                    Text(leisureStatusText)
                        .font(.tempoCaption1)
                        .foregroundStyle(leisureStatusTextColor)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, TempoSpacing.screenEdge)

            // Progress bar
            if viewModel.activeOverride == nil {
                LinearProgressBar(
                    progress: viewModel.completionPercentage,
                    color: leisureProgressColor,
                    height: 5,
                    showPercentage: false
                )
                .padding(.horizontal, TempoSpacing.screenEdge)
            }
        }
        .padding(.vertical, TempoSpacing.sm)
        .background(
            leisureBackgroundTint
                .opacity(0.03)
                .background(Color.tempoBgPrimary)
        )
    }

    private var leisureLockIcon: String {
        if viewModel.isLeisureUnlocked || viewModel.activeOverride != nil {
            return "lock.open.fill"
        }
        return "lock.fill"
    }

    private var leisureLockColor: Color {
        if viewModel.isLeisureUnlocked {
            return .tempoSuccess
        }
        if viewModel.activeOverride != nil {
            return .tempoTextTertiary
        }
        if viewModel.dailyState == .dayFailed {
            return .tempoSignal
        }
        return .tempoSignal
    }

    private var leisureStatusText: String {
        if viewModel.activeOverride != nil {
            return "Rest day. No non-negotiables active."
        }
        if viewModel.isLeisureUnlocked {
            return "You earned it. Enjoy your evening."
        }
        if viewModel.dailyState == .dayFailed {
            return "PS5 time has passed. Tasks still incomplete."
        }
        let remaining = viewModel.totalCount - viewModel.completedCount
        if remaining == 1 {
            return "Just 1 more. You're right there."
        }
        return "Complete \(remaining) more to unlock"
    }

    private var leisureStatusTextColor: Color {
        if viewModel.isLeisureUnlocked {
            return .tempoSuccess
        }
        if viewModel.dailyState == .dayFailed {
            return .tempoSignal
        }
        let remaining = viewModel.totalCount - viewModel.completedCount
        if remaining == 1 {
            return .tempoAmber
        }
        return .tempoTextPrimary
    }

    private var leisureProgressColor: Color {
        let pct = viewModel.completionPercentage
        if pct >= 1.0 {
            return .tempoSuccess
        }
        if pct >= 0.5 {
            return .tempoAmber
        }
        return .tempoSignal
    }

    private var leisureBackgroundTint: Color {
        if viewModel.isLeisureUnlocked {
            return .tempoSuccess
        }
        if viewModel.dailyState == .dayFailed {
            return .tempoSignal
        }
        return .clear
    }

    // MARK: - Unlock Celebration

    // Per MODULE_ACCOUNTABILITY.md — confetti + glow on leisure unlock.
    // Per SOUND_AND_HAPTICS.md — triple success haptic.
    // Enhanced with confetti particle animation, score display, and streak update.

    private var unlockCelebrationOverlay: some View {
        ZStack {
            // Dark background
            Color.tempoInk.opacity(0.85)
                .ignoresSafeArea()

            // Confetti particle system
            ConfettiCanvasView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Content
            VStack(spacing: TempoSpacing.lg) {
                Spacer()

                // Controller icon
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Color.tempoSuccess)
                    .shadow(color: Color.tempoSuccess.opacity(0.6), radius: 24)
                    .scaleEffect(showUnlockCelebration ? 1.0 : 0.3)
                    .animation(.spring(response: 0.5, dampingFraction: 0.5), value: showUnlockCelebration)

                // Lock icon
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.tempoSuccess.opacity(0.7))

                Text("PS5 UNLOCKED")
                    .font(.tempoTitle1)
                    .foregroundStyle(Color.tempoSuccess)

                Text("You earned it. Enjoy your evening.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)

                // Score display
                if let accountability = viewModel.accountability {
                    let score = services.accountabilityEngine.calculateDailyScore(accountability: accountability)
                    VStack(spacing: TempoSpacing.xs) {
                        Text("TODAY'S SCORE")
                            .font(.tempoCaption2)
                            .tracking(1)
                            .foregroundStyle(Color.tempoTextTertiary)

                        Text("\(score)")
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .padding(.top, TempoSpacing.md)
                }

                // Streak badge
                if viewModel.streakCount > 0 {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.tempoAmber)

                        Text("Day \(viewModel.streakCount)!")
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoAmber)
                    }
                    .padding(.horizontal, TempoSpacing.lg)
                    .padding(.vertical, TempoSpacing.sm)
                    .background(Color.tempoAmber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }

                Spacer()
            }
            .transition(.scale.combined(with: .opacity))
        }
        .onTapGesture {
            withAnimation { showUnlockCelebration = false }
        }
    }
}

// MARK: - ConfettiCanvasView

// Particle-based confetti animation using Canvas for the unlock celebration.

struct ConfettiCanvasView: View {
    @State
    private var particles: [ConfettiParticle] = []
    @State
    private var animationTimer: Timer?

    struct ConfettiParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var velocityX: CGFloat
        var velocityY: CGFloat
        var rotation: Double
        var rotationSpeed: Double
        var scale: CGFloat
        var color: Color
        var shape: ConfettiShape
        var opacity: Double = 1.0

        enum ConfettiShape: CaseIterable {
            case circle
            case rectangle
            case triangle
        }
    }

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, _ in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.x - particle.scale * 4,
                        y: particle.y - particle.scale * 4,
                        width: particle.scale * 8,
                        height: particle.scale * 8
                    )

                    context.opacity = particle.opacity

                    switch particle.shape {
                    case .circle:
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(particle.color)
                        )
                    case .rectangle:
                        var transform = CGAffineTransform.identity
                        transform = transform.translatedBy(x: particle.x, y: particle.y)
                        transform = transform.rotated(by: particle.rotation)
                        transform = transform.translatedBy(x: -particle.x, y: -particle.y)

                        var path = Path()
                        path.addRect(rect)
                        path = path.applying(transform)

                        context.fill(path, with: .color(particle.color))
                    case .triangle:
                        var path = Path()
                        path.move(to: CGPoint(x: particle.x, y: particle.y - particle.scale * 5))
                        path.addLine(to: CGPoint(x: particle.x - particle.scale * 4, y: particle.y + particle.scale * 3))
                        path.addLine(to: CGPoint(x: particle.x + particle.scale * 4, y: particle.y + particle.scale * 3))
                        path.closeSubpath()

                        context.fill(path, with: .color(particle.color))
                    }
                }
            }
        }
        .onAppear { spawnParticles() }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func spawnParticles() {
        let screenWidth = UIScreen.main.bounds.width
        let colors: [Color] = [.tempoSuccess, .tempoElectric, .tempoAmber, .tempoSignal, .tempoViolet, .white]

        // Spawn initial burst
        for _ in 0 ..< 80 {
            particles.append(ConfettiParticle(
                x: CGFloat.random(in: 0 ... screenWidth),
                y: CGFloat.random(in: -200 ... -20),
                velocityX: CGFloat.random(in: -3 ... 3),
                velocityY: CGFloat.random(in: 2 ... 8),
                rotation: Double.random(in: 0 ... (.pi * 2)),
                rotationSpeed: Double.random(in: -0.1 ... 0.1),
                scale: CGFloat.random(in: 0.5 ... 1.5),
                color: colors.randomElement()!,
                shape: ConfettiParticle.ConfettiShape.allCases.randomElement()!
            ))
        }

        // Animate
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                for i in particles.indices {
                    particles[i].x += particles[i].velocityX
                    particles[i].y += particles[i].velocityY
                    particles[i].velocityY += 0.15 // gravity
                    particles[i].velocityX *= 0.99 // air resistance
                    particles[i].rotation += particles[i].rotationSpeed

                    // Fade out near bottom
                    let screenHeight = UIScreen.main.bounds.height
                    if particles[i].y > screenHeight * 0.7 {
                        particles[i].opacity = max(0, particles[i].opacity - 0.02)
                    }
                }

                // Remove dead particles
                particles.removeAll { $0.opacity <= 0 || $0.y > UIScreen.main.bounds.height + 50 }
            }
        }
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

    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(ServiceContainer.self)
    private var services

    private var nn: NonNegotiable? {
        progress.nonNegotiable
    }

    private var cardState: CardState {
        resolveCardState()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            // Row 1: Icon + Name + Status
            headerRow

            // Row 2: Progress bar
            if cardState != .skipped {
                progressRow
            }

            // Row 3: Supporting text + Action
            supportingRow

            // Expanded detail
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(cardBorder)
        .shadow(
            color: Color.tempoInk.opacity(colorScheme == .dark ? 0 : 0.06),
            radius: 4, x: 0, y: 2
        )
        .opacity(cardState == .skipped ? 0.6 : 1.0)
        .onTapGesture { onTap() }
        .contextMenu { cardContextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: TempoSpacing.md) {
            // Icon
            Image(systemName: nn?.icon ?? "star.fill")
                .font(.system(size: 28))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)

            // Name
            Text(nn?.name ?? "Task")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
                .strikethrough(cardState == .skipped)

            // Mini streak badge
            if habitStreakCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.tempoAmber)
                    Text("\(habitStreakCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.tempoAmber)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.tempoAmber.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm, style: .continuous))
            }

            Spacer()

            // Status indicator
            statusIndicator
        }
    }

    private var iconColor: Color {
        switch cardState {
        case .notStarted: .tempoTextTertiary
        case .inProgress: .tempoElectric
        case .completed: .tempoSuccess
        case .overdue: .tempoSignal
        case .skipped: .tempoTextTertiary
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch cardState {
        case .notStarted:
            Text("NOT STARTED")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        case .inProgress:
            Text(progressText)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
        case .completed:
            HStack(spacing: TempoSpacing.xs) {
                Text("DONE")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSuccess)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.tempoSuccess)
            }
        case .overdue:
            Text("OVERDUE")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoSignal)
        case .skipped:
            Text("SKIPPED")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
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
        HStack(spacing: TempoSpacing.sm) {
            // Source badge
            sourceBadge

            // Progress bar
            LinearProgressBar(
                progress: progress.targetValue > 0
                    ? progress.currentValue / progress.targetValue
                    : 0,
                color: progressBarColor,
                height: 6,
                showPercentage: false
            )

            // Percentage
            Text("\(Int(min(1, progress.targetValue > 0 ? progress.currentValue / progress.targetValue : 0) * 100))%")
                .font(.tempoFootnote)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var progressBarColor: Color {
        let pct = progress.targetValue > 0 ? progress.currentValue / progress.targetValue : 0
        if pct >= 0.8 {
            return .tempoSuccess
        }
        if pct >= 0.5 {
            return .tempoAmber
        }
        return .tempoElectric
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let nn {
            let badgeText = switch nn.type {
            case .train: "WHOOP"
            case .meals: "NUTRITRACK"
            case .study: "MANUAL"
            case .sleep: "HEALTHKIT"
            case .steps: "HEALTHKIT"
            case .hydration: "MANUAL"
            case .custom: "MANUAL"
            }

            Text(badgeText)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.tempoBorder)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous))
        }
    }

    // MARK: - Supporting Row

    private var supportingRow: some View {
        HStack {
            Text(supportingText)
                .font(.tempoFootnote)
                .foregroundStyle(Color.tempoTextSecondary)
                .lineLimit(1)

            Spacer()

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
                        pillButton(title: "Add More", style: .outline) { onStartTimer() }
                    } else {
                        pillButton(title: "Start Timer", style: .filled) { onStartTimer() }
                    }
                }
            case .train:
                if !progress.isCompleted {
                    pillButton(title: "Log Manually", style: .filled) {
                        onComplete()
                    }
                }
            case .meals:
                if !progress.isCompleted {
                    pillButton(title: "Log Meal", style: .filled) { onLogMeal() }
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
                }
            case .custom:
                switch nn.trackingMethod {
                case .timer:
                    if let onStartTimer, !progress.isCompleted {
                        pillButton(title: "Start Timer", style: .filled) { onStartTimer() }
                    }
                case .manual:
                    if !progress.isCompleted {
                        pillButton(title: "+", style: .filled) {
                            onUpdateValue(progress.currentValue + 1)
                        }
                    }
                case .autoWhoop,
                     .autoHealthkit:
                    EmptyView()
                }
            }
        }
    }

    enum PillStyle { case filled, outline }

    private func pillButton(title: String, style: PillStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tempoCaption1)
                .foregroundStyle(style == .filled ? .white : Color.tempoElectric)
                .padding(.horizontal, TempoSpacing.md)
                .frame(height: 28)
                .background(style == .filled ? Color.tempoElectric : .clear)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                .overlay(
                    style == .outline
                        ? RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous)
                        .stroke(Color.tempoElectric, lineWidth: 1)
                        : nil
                )
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Divider()

            // Quick actions
            HStack(spacing: TempoSpacing.md) {
                if !progress.isCompleted {
                    Button {
                        HapticManager.notification(.success)
                        onComplete()
                    } label: {
                        Label("Mark Complete", systemImage: "checkmark.circle")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoSuccess)
                    }

                    Button {
                        HapticManager.notification(.warning)
                        onSkip()
                    } label: {
                        Label("Skip Today", systemImage: "forward.fill")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
        }
        .padding(.top, TempoSpacing.sm)
    }

    // MARK: - Card Visual State

    private var cardBackground: Color {
        switch cardState {
        case .completed: Color.tempoSuccess.opacity(0.05)
        case .overdue: Color.tempoSignal.opacity(0.03)
        default: Color.tempoSurfaceCard
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
            .stroke(borderColor, lineWidth: 1)
    }

    private var borderColor: Color {
        switch cardState {
        case .notStarted,
             .skipped: .tempoBorder
        case .inProgress: .tempoElectric
        case .completed: .tempoSuccess
        case .overdue: .tempoSignal
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
