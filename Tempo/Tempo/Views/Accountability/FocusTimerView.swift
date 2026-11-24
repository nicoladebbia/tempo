//
// FocusTimerView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI
import UIKit

// MARK: - Focus Timer View

// Per BUILD_PLAN step 10.4.
// Per MODULE_ACCOUNTABILITY.md — Focus Timer / Pomodoro.
// Per STATE_MACHINES.md Section 2 — Focus Timer state machine.
// Per WIREFRAMES.md — Focus Timer screen.

struct FocusTimerView: View {
    @Bindable
    var viewModel: AccountabilityViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .largeTitle)
    private var numeralScale: CGFloat = 1

    @State
    private var showStopConfirmation = false
    @State
    private var showCloseConfirmation = false
    @State
    private var showSettings = false
    @State
    private var showSubjectPicker = false
    @State
    private var colonVisible = true
    @State
    private var blinkTask: Task<Void, Never>?

    /// Break messages pool
    private let breakMessages = [
        "Stand up. Stretch. You've earned it.",
        "Hydrate. Your brain needs water.",
        "Look at something 20 feet away for 20 seconds.",
        "Roll your neck. Release the tension.",
        "Deep breath in... hold... and out.",
    ]

    @State
    private var breakMessageIndex = Int.random(in: 0 ..< 5)

    var body: some View {
        ZStack {
            // Phase-tinted glow behind the dial
            phaseBackground
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if isReview {
                // Review overlay
                reviewOverlay
            } else {
                timerScreen
            }

            // Completion overlay
            if case let .completed(totalSessions) = viewModel.focusState {
                completionOverlay(totalSessions: totalSessions)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .tidePage(energy: 1)
        // The field rests while a sheet is over the timer.
        .tideCovered(showSettings || showSubjectPicker)
        .confirmationDialog(
            "Stop this session?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            stopConfirmationButtons
        } message: {
            if elapsedMinutes >= 5 {
                Text("\(elapsedMinutes) minutes of study will be saved.")
            }
        }
        .confirmationDialog(
            "Timer is running.",
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Going", role: .cancel) {}
            Button("Stop & Discard", role: .destructive) {
                viewModel.cancelFocus(modelContext: modelContext)
                dismiss()
            }
        } message: {
            Text("Stop and discard this session?")
        }
        .sheet(isPresented: $showSettings) {
            focusSettingsSheet
        }
        .sheet(isPresented: $showSubjectPicker) {
            subjectPickerSheet
        }
        .onChange(of: viewModel.focusState) { _, newState in
            handleStateChange(newState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Per spec B50 — App Store-safe distraction auto-detection.
            // Every backgrounding while focusing increments the counter,
            // catching the "switched to social media" pattern that the
            // manual "Distracted" button can't.
            guard newPhase == .background || newPhase == .inactive else {
                return
            }
            if case .focusing = viewModel.focusState {
                viewModel.distractionCount += 1
            }
        }
        .onAppear {
            // Start colon blink timer for paused state
            startColonBlink()
        }
        .onDisappear {
            blinkTask?.cancel()
            blinkTask = nil
            // Always release the screen lock when the timer view leaves.
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Timer Screen

    private var timerScreen: some View {
        GeometryReader { proxy in
            let diameter = dialDiameter(in: proxy.size)
            ScrollView {
                VStack(spacing: 0) {
                    // Navigation bar
                    navigationBar
                        .padding(.horizontal, Tide.edge)

                    // Everything down to the dial is top-aligned and the same
                    // height in every state, so the dial never moves when the
                    // timer starts, pauses or goes on a break.
                    Color.clear.frame(height: max(Tide.s6, proxy.size.height * 0.04))

                    // Session label and the run's sessions as dots
                    sessionLabel
                        .padding(.bottom, Tide.s2)

                    LockdownSessionDots(
                        completed: min(viewModel.currentSessionCount, viewModel.sessionsBeforeLongBreak),
                        total: viewModel.sessionsBeforeLongBreak,
                        running: viewModel.focusState.isActive
                    )
                    .padding(.bottom, Tide.s3)

                    // Subject pill
                    if let subject = viewModel.focusSubject {
                        subjectPill(subject)
                            .padding(.bottom, Tide.s4)
                    }

                    // Timer dial
                    timerDial(diameter: diameter)
                        .padding(.bottom, Tide.s4)

                    // Phase, today's total, and the focus score or break line
                    // in one slot: what changes lives below the dial.
                    VStack(spacing: Tide.s3) {
                        phaseLabel
                        accumulatedTime
                        statusLine
                    }

                    // Whatever is left of the page sits between the status and
                    // the buttons.
                    Spacer(minLength: Tide.s4)

                    // Smart recommendation: next to the Start button, in thumb reach
                    if isIdleOrConfiguring {
                        focusRecommendationBanner
                            .padding(.horizontal, Tide.edge)
                            .padding(.bottom, Tide.s3)
                    }

                    // Secondary buttons (distraction + ambient)
                    if viewModel.focusState.isActive {
                        secondaryButtons
                            .padding(.horizontal, Tide.edge)
                            .padding(.bottom, Tide.s3)
                    }
                }
                .frame(minHeight: proxy.size.height)
                .animation(Tide.snap, value: viewModel.focusState.isActive)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        // Start, Pause and Stop stay under the thumb, even when large text
        // makes the page scroll. The bar is the same height in every state, so
        // the dial is not resized by it, and the scrim keeps the page from
        // reading through the buttons.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            primaryControls
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s4)
                .pinnedBarScrim()
        }
    }

    /// One line under the total, always reserved: the focus score while focusing, a break line on a break.
    @ViewBuilder
    private var statusLine: some View {
        if case .focusing = viewModel.focusState {
            focusScoreDisplay
        } else if isBreakState {
            breakMessageView
        } else {
            Color.clear.frame(height: Tide.s5)
        }
    }

    /// The dial grows to 300pt on a roomy phone and shrinks on a short or narrow one.
    private func dialDiameter(in size: CGSize) -> CGFloat {
        min(Tide.dialTimer, size.width - Tide.edge * 2, size.height * 0.42)
    }

    // MARK: - Smart Focus Recommendation Banner

    // Shows context-aware timer recommendation based on study progress today.

    private var focusRecommendationBanner: some View {
        let recommendation = focusRecommendation

        // Icon, words and the suggested length in a line, or one under the other at large text.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))

        return layout {
            Image(systemName: recommendation.icon)
                .font(Tide.headline)
                .foregroundStyle(recommendation.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(recommendation.title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recommendation.subtitle)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }

            if let suggestedMinutes = recommendation.suggestedDuration {
                Button {
                    viewModel.focusDuration = TimeInterval(suggestedMinutes * 60)
                    HapticManager.impact(.light)
                } label: {
                    Text("\(suggestedMinutes)m")
                        .font(Tide.numeral(Tide.numeralS - Tide.s1, .bold))
                        .foregroundStyle(Tide.ink)
                        .padding(.horizontal, Tide.s3)
                        .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                        .background(recommendation.color, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set timer to \(suggestedMinutes) minutes")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideTintedCard(recommendation.color, padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .contain)
    }

    private struct FocusRecommendation {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let suggestedDuration: Int?
    }

    private var focusRecommendation: FocusRecommendation {
        let totalMinutes = viewModel.totalFocusMinutesToday
        let target = studyTargetMinutes
        let remaining = max(0, target - totalMinutes)
        let timeToPS5 = viewModel.timeToPS5

        // Already hit target
        if remaining <= 0 {
            return FocusRecommendation(
                title: "Target reached! Extra credit time.",
                subtitle: "You've hit \(totalMinutes)m / \(target)m. Any session now is bonus.",
                icon: "star.fill",
                color: TideTone.mint,
                suggestedDuration: 25
            )
        }

        // Very close to target (15 min or less)
        if remaining <= 15 {
            return FocusRecommendation(
                title: "Just \(remaining)m left. Finish strong.",
                subtitle: "One short sprint to complete your study goal.",
                icon: "flag.checkered",
                color: TideTone.mint,
                suggestedDuration: remaining
            )
        }

        // Haven't started today
        if totalMinutes == 0 {
            let suggestedDuration: Int
            let subtitle: String

            if remaining > 90 {
                suggestedDuration = 25
                subtitle = "You need \(remaining)m total. Start with a 25m sprint to build momentum."
            } else if remaining > 45 {
                suggestedDuration = 25
                subtitle = "You need \(remaining)m today. Start with a 25m pomodoro."
            } else {
                suggestedDuration = min(remaining, 25)
                subtitle = "You need \(remaining)m today. A quick sprint will get you started."
            }

            // Time pressure context
            if timeToPS5 < 2 * 3600, remaining > 30 {
                return FocusRecommendation(
                    title: "\(remaining)m needed. \(PS5Countdown.only(timeToPS5))",
                    subtitle: "Start NOW. Every minute counts.",
                    icon: "exclamationmark.triangle.fill",
                    color: Tide.danger,
                    suggestedDuration: min(remaining, 50)
                )
            }

            return FocusRecommendation(
                title: "You need \(remaining)m today. Let's go.",
                subtitle: subtitle,
                icon: "play.circle.fill",
                color: mood.accent,
                suggestedDuration: suggestedDuration
            )
        }

        // Partially done — recommend based on remaining
        let suggestedDuration: Int = if remaining > 60 {
            50 // Deep work session
        } else if remaining > 30 {
            25 // Standard pomodoro
        } else {
            remaining // Just finish it
        }

        // Time pressure
        if timeToPS5 < 1.5 * 3600, remaining > 20 {
            return FocusRecommendation(
                title: "\(remaining)m remaining. Clock's ticking.",
                subtitle: "\(PS5Countdown.lessThan(timeToPS5)) Buckle down.",
                icon: "exclamationmark.triangle.fill",
                color: TideTone.amber,
                suggestedDuration: min(remaining, 50)
            )
        }

        return FocusRecommendation(
            title: "\(remaining)m remaining. Time for \(suggestedDuration >= 45 ? "a deep work session" : "a sprint").",
            subtitle: "\(totalMinutes)m done so far. Keep the momentum.",
            icon: "bolt.fill",
            color: mood.accent,
            suggestedDuration: suggestedDuration
        )
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button {
                if viewModel.focusState.isActive || isPaused {
                    showCloseConfirmation = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close timer")

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Timer settings")
        }
    }

    // MARK: - Session Label

    @ViewBuilder
    private var sessionLabel: some View {
        if viewModel.currentSessionCount >= viewModel.sessionsBeforeLongBreak {
            Text("Bonus session")
                .tideLabel(TideTone.amber)
        } else {
            Text("Session \(viewModel.currentSessionCount + 1) of \(viewModel.sessionsBeforeLongBreak)")
                .tideLabel()
        }
    }

    // MARK: - Subject Pill

    private func subjectPill(_ subject: String) -> some View {
        Button {
            showSubjectPicker = true
        } label: {
            HStack(spacing: Tide.s2) {
                Text(subject)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)

                Image(systemName: "chevron.down")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Tide.s4)
            .frame(minHeight: Tide.hit)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Subject: \(subject)")
        .accessibilityHint("Choose a different subject")
    }

    // MARK: - Subject Picker

    private static let studySubjects = [
        "Math", "CS", "Languages", "Physics", "Chemistry",
        "Biology", "History", "Literature", "Economics", "Engineering",
    ]

    private var subjectPickerSheet: some View {
        NavigationStack {
            TideScrollPage {
                VStack(spacing: 0) {
                    ForEach(Array(Self.studySubjects.enumerated()), id: \.element) { index, subject in
                        if index > 0 {
                            TideDivider()
                        }
                        Button {
                            viewModel.focusSubject = subject
                            viewModel.currentStudySession?.subject = subject
                            showSubjectPicker = false
                        } label: {
                            HStack {
                                Text(subject)
                                    .font(Tide.body)
                                    .foregroundStyle(Tide.text)
                                Spacer()
                                if viewModel.focusSubject == subject {
                                    Image(systemName: "checkmark")
                                        .font(Tide.bodyStrong)
                                        .foregroundStyle(mood.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: Tide.hit)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(viewModel.focusSubject == subject ? .isSelected : [])
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
            .navigationTitle("Study Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSubjectPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Timer Dial

    // Per MODULE_ACCOUNTABILITY.md — the timer is the screen: a large
    // shader-lit dial, lit tick by tick, with the time in condensed numerals.

    private func timerDial(diameter: CGFloat) -> some View {
        TideTimerDial(
            progress: viewModel.focusTimerProgress,
            accent: ringColor,
            diameter: diameter
        ) {
            timerText(diameter: diameter)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phaseLabelText)
        .accessibilityValue(spokenTime)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Before Start the dial shows the length of the session that will run, not 0:00.
    private var timerString: String {
        guard isIdleOrConfiguring else {
            return viewModel.formattedFocusTimer
        }
        let total = Int(viewModel.focusDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var timerParts: (minutes: String, seconds: String) {
        let parts = timerString.split(separator: ":")
        let minutes = parts.first.map(String.init) ?? "0"
        let seconds = parts.count > 1 ? String(parts[1]) : "00"
        return (minutes, seconds)
    }

    private var spokenTime: String {
        let parts = timerParts
        return "\(Int(parts.minutes) ?? 0) minutes \(Int(parts.seconds) ?? 0) seconds"
    }

    private func timerText(diameter: CGFloat) -> some View {
        let parts = timerParts
        let font = Tide.numeral(diameter * 0.27 * min(numeralScale, 1.25), .bold)

        return HStack(spacing: 0) {
            Text(parts.minutes)
                .font(font)
                .foregroundStyle(Tide.text)
                .contentTransition(.numericText(countsDown: true))

            Text(":")
                .font(font)
                .foregroundStyle(Tide.text)
                .opacity(isPaused ? (colonVisible ? 1 : 0.3) : 1)

            Text(parts.seconds)
                .font(font)
                .foregroundStyle(Tide.text)
                .contentTransition(.numericText(countsDown: true))
        }
        .lineLimit(1)
        .minimumScaleFactor(Tide.labelShrink)
        .animation(Tide.snap, value: timerString)
    }

    private var ringColor: Color {
        if isPaused {
            return TideTone.amber
        }
        if isBreakState {
            return TideTone.mint
        }
        return mood.accent
    }

    // MARK: - Phase Label

    // Per MODULE_ACCOUNTABILITY.md — phase label below the dial.

    private var phaseLabel: some View {
        Text(phaseLabelText)
            .tideLabel(phaseLabelColor)
    }

    private var phaseLabelText: String {
        switch viewModel.focusState {
        case .idle,
             .configuring: "Ready"
        case .focusing: "Focus time"
        case .onBreak,
             .longBreak: "Break time"
        case .paused: "Paused"
        case .sessionDone: "Session done"
        case .breakDone: "Break done"
        case .completed: "Complete"
        case .review: "Review"
        case .cancelled: "Cancelled"
        }
    }

    private var phaseLabelColor: Color {
        switch viewModel.focusState {
        case .focusing: mood.accent
        case .onBreak,
             .longBreak,
             .breakDone: TideTone.mint
        case .paused: TideTone.amber
        case .completed: TideTone.mint
        default: Tide.text2
        }
    }

    // MARK: - Accumulated Time

    private var accumulatedTime: some View {
        let totalMinutes = viewModel.totalFocusMinutesToday
        let targetMinutes = studyTargetMinutes
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        let targetH = targetMinutes / 60
        let targetM = targetMinutes % 60

        let currentText = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        let targetText = targetH > 0 ? "\(targetH)h \(targetM)m" : "\(targetM)m"

        let fraction = targetMinutes > 0 ? min(1, Double(totalMinutes) / Double(targetMinutes)) : 0

        return VStack(spacing: Tide.s2) {
            Text("Today's total: \(currentText) / \(targetText)")
                .font(Tide.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)

            TideLevelBar(progress: fraction, color: mood.accent, height: Tide.barSlim)
                .frame(maxWidth: Tide.dialHero)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Tide.edge)
    }

    private var studyTargetMinutes: Int {
        let studyProgress = viewModel.progressItems.first(where: {
            $0.nonNegotiable?.type == .study
        })
        return Int(studyProgress?.targetValue ?? 120)
    }

    // MARK: - Focus Score

    private var focusScoreDisplay: some View {
        let score = max(0, 100 - (viewModel.distractionCount * 10))
        return Text("Focus Score: \(score)")
            .font(Tide.bodyStrong)
            .monospacedDigit()
            .foregroundStyle(Tide.text)
    }

    // MARK: - Break Message

    private var breakMessageView: some View {
        Text(breakMessages[breakMessageIndex % breakMessages.count])
            .font(Tide.body)
            .foregroundStyle(Tide.text2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Tide.s8)
    }

    // MARK: - Secondary Buttons

    private var secondaryButtons: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s3))

        return GlassEffectContainer(spacing: Tide.s3) {
            layout {
                // Distraction button
                Button {
                    HapticManager.impact(.light)
                    viewModel.distractionCount += 1
                } label: {
                    HStack(spacing: Tide.s2) {
                        Image(systemName: "hand.raised.fill")
                            .accessibilityHidden(true)

                        Text("Distracted")

                        if viewModel.distractionCount > 0 {
                            Text("\(viewModel.distractionCount)")
                                .font(Tide.numeral(Tide.numeralS - Tide.s2, .bold))
                                .foregroundStyle(Tide.ink)
                                .frame(minWidth: Tide.s5, minHeight: Tide.s5)
                                .background(Tide.danger, in: .circle)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityValue(
                    viewModel.distractionCount > 0 ? "\(viewModel.distractionCount) so far" : ""
                )

                // Ambient button (placeholder)
                Button {
                    HapticManager.impact(.light)
                } label: {
                    HStack(spacing: Tide.s2) {
                        Image(systemName: "speaker.wave.2.fill")
                            .accessibilityHidden(true)

                        Text("Ambient")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
            }
        }
    }

    // MARK: - Primary Controls

    // Per MODULE_ACCOUNTABILITY.md — Stop, Main, Skip.

    private var primaryControls: some View {
        GlassEffectContainer(spacing: Tide.s3) {
            HStack(spacing: Tide.s3) {
                // Stop button
                if viewModel.focusState.isActive || isPaused {
                    Button {
                        HapticManager.impact(.light)
                        showStopConfirmation = true
                    } label: {
                        Image(systemName: isPaused ? "xmark.circle" : "square.fill")
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .frame(width: Tide.hit + Tide.s2, height: Tide.hit + Tide.s2)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop")
                }

                // Main button
                mainButton

                // Skip button
                if viewModel.focusState.isActive {
                    Button {
                        HapticManager.impact(.light)
                        skipAction()
                    } label: {
                        Image(systemName: isBreakState ? "arrow.right.circle.fill" : "forward.fill")
                            .font(Tide.headline)
                            .foregroundStyle(isBreakState ? Tide.ink : Tide.text)
                            .frame(width: Tide.hit + Tide.s2, height: Tide.hit + Tide.s2)
                            .background {
                                if isBreakState {
                                    Circle().fill(TideTone.mint)
                                }
                            }
                            .glassEffect(isBreakState ? .identity : .regular.interactive(), in: .circle)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip")
                }
            }
        }
    }

    @ViewBuilder
    private var mainButton: some View {
        if isBreakState {
            Button(action: performMainButton) { mainButtonLabel.foregroundStyle(TideTone.mint) }
                .buttonStyle(.tideGlass)
        } else {
            Button(action: performMainButton) { mainButtonLabel }
                .buttonStyle(.tidePrimary)
        }
    }

    private var mainButtonLabel: some View {
        Text(mainButtonTitle)
            .frame(maxWidth: .infinity)
    }

    private func performMainButton() {
        HapticManager.impact(.heavy)
        mainButtonAction()
    }

    private var mainButtonTitle: String {
        switch viewModel.focusState {
        case .idle,
             .configuring: "Start"
        case .focusing: "Pause"
        case .paused: "Resume"
        case .onBreak,
             .longBreak: "Skip break"
        case .sessionDone: "Start break"
        case .breakDone: "Start focus"
        case .completed: "Review"
        case .review: "Done"
        case .cancelled: "Start"
        }
    }

    // MARK: - Actions

    private func mainButtonAction() {
        switch viewModel.focusState {
        case .idle,
             .configuring,
             .cancelled:
            viewModel.startFocusSession(modelContext: modelContext)
        case .focusing:
            viewModel.pauseFocus()
        case .paused:
            viewModel.resumeFocus(modelContext: modelContext)
        case .onBreak,
             .longBreak:
            viewModel.skipBreak(modelContext: modelContext)
        case .sessionDone:
            viewModel.startBreak()
        case .breakDone:
            viewModel.startFocusSession(modelContext: modelContext)
        case .completed:
            viewModel.focusState = .review
        case .review:
            viewModel.finishFocusReview(modelContext: modelContext)
            dismiss()
        }
    }

    private func skipAction() {
        if isBreakState {
            viewModel.skipBreak(modelContext: modelContext)
        }
        // During focus — could skip to session done, but keeping simple
    }

    // MARK: - Stop Confirmation

    @ViewBuilder
    private var stopConfirmationButtons: some View {
        Button("Keep Going", role: .cancel) {}

        if elapsedMinutes >= 5 {
            Button("Stop & Save") {
                viewModel.finishFocusReview(modelContext: modelContext)
                dismiss()
            }
        }

        Button("Stop & Discard", role: .destructive) {
            viewModel.cancelFocus(modelContext: modelContext)
            dismiss()
        }
    }

    // MARK: - Completion Overlay

    // Per MODULE_ACCOUNTABILITY.md — celebration on all sessions complete.
    // Per SOUND_AND_HAPTICS.md — triple success haptic.

    private func completionOverlay(totalSessions: Int) -> some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Tide.ink.opacity(0.55))
                .ignoresSafeArea()

            ArenaBurst(accent: TideTone.mint)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Tide.s5) {
                        Spacer(minLength: Tide.s6)

                        // The ring closes around the check: the run is sealed.
                        LockdownSeal(systemImage: "checkmark", diameter: Tide.dialHero)

                        Text("All sessions complete!")
                            .font(Tide.title2)
                            .foregroundStyle(Tide.text)
                            .multilineTextAlignment(.center)
                            .arenaReveal(5)

                        Text("\(totalSessions) sessions of focused study")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .arenaReveal(7)

                        LockdownSessionDots(completed: totalSessions, total: totalSessions, running: false)
                            .arenaReveal(9)

                        Spacer(minLength: Tide.s6)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, Tide.edge)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            // The one way on stays under the thumb.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Done") {
                    viewModel.focusState = .review
                }
                .buttonStyle(.tidePrimary)
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s4)
            }
            .accessibilityElement(children: .contain)
        }
        .transition(.opacity)
    }

    // MARK: - Review Overlay

    private var reviewOverlay: some View {
        let score = max(0, 100 - (viewModel.distractionCount * 10))

        return ScrollView {
            VStack(spacing: Tide.s5) {
                Text("Session review")
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .padding(.top, Tide.s10)

                // Focus score dial
                VStack(spacing: Tide.s2) {
                    TideDial(score: score, caption: "Focus score", diameter: Tide.dialDetail)

                    Text(scoreLabel(score))
                        .font(Tide.headline)
                        .foregroundStyle(scoreColor(score))
                }

                // The run in one card
                VStack(spacing: 0) {
                    reviewStatRow(
                        title: "Total Focus Time",
                        value: "\(viewModel.currentSessionCount * Int(viewModel.focusDuration / 60))m",
                        icon: "clock.fill"
                    )

                    TideDivider()

                    reviewStatRow(
                        title: "Sessions Completed",
                        value: "\(viewModel.currentSessionCount)",
                        icon: "checkmark.circle.fill"
                    )

                    TideDivider()

                    reviewStatRow(
                        title: "Distractions",
                        value: "\(viewModel.distractionCount)",
                        icon: "hand.raised.fill"
                    )
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s4)
        }
        .scrollIndicators(.hidden)
        // The one action stays under the thumb however long the content grows.
        .safeAreaInset(edge: .bottom) {
            Button("Done") {
                viewModel.finishFocusReview(modelContext: modelContext)
                dismiss()
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s4)
        }
    }

    private func reviewStatRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: Tide.s3) {
            TideAreaIconTile(systemName: icon, tint: mood.accent)

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title).tideLabel(Tide.text3)

                TideNumber(value, size: Tide.numeralM, relativeTo: .title)
            }

            Spacer(minLength: Tide.s2)
        }
        .padding(.vertical, Tide.s3)
        .accessibilityElement(children: .combine)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 {
            return TideTone.mint
        }
        if score >= 75 {
            return mood.accent
        }
        if score >= 50 {
            return TideTone.amber
        }
        return Tide.danger
    }

    private func scoreLabel(_ score: Int) -> String {
        if score >= 90 {
            return "Excellent"
        }
        if score >= 75 {
            return "Good"
        }
        if score >= 50 {
            return "Fair"
        }
        return "Needs work"
    }

    // MARK: - Phase Background

    private var phaseBackground: some View {
        Group {
            switch viewModel.focusState {
            case .focusing:
                phaseGlow(mood.accent)
            case .onBreak,
                 .longBreak:
                phaseGlow(TideTone.mint)
            case .paused:
                phaseGlow(TideTone.amber)
            default:
                Color.clear
            }
        }
        .animation(Tide.settle, value: ringColor)
    }

    private func phaseGlow(_ color: Color) -> some View {
        RadialGradient(
            colors: [color.opacity(0.14), .clear],
            center: .center,
            startRadius: Tide.s10,
            endRadius: Tide.dialTimer * 1.2
        )
    }

    // MARK: - Settings Sheet

    private var focusSettingsSheet: some View {
        NavigationStack {
            TideScrollPage {
                TideSectionLabel(title: "Timer")

                VStack(spacing: 0) {
                    settingsStepper(
                        title: "Focus Duration",
                        value: Binding(
                            get: { Int(viewModel.focusDuration / 60) },
                            set: { viewModel.focusDuration = TimeInterval($0 * 60) }
                        ),
                        range: 15 ... 60,
                        step: 5,
                        unit: " min"
                    )

                    TideDivider()

                    settingsStepper(
                        title: "Short Break",
                        value: Binding(
                            get: { Int(viewModel.breakDuration / 60) },
                            set: { viewModel.breakDuration = TimeInterval($0 * 60) }
                        ),
                        range: 3 ... 15,
                        step: 1,
                        unit: " min"
                    )

                    TideDivider()

                    settingsStepper(
                        title: "Long Break",
                        value: Binding(
                            get: { Int(viewModel.longBreakDuration / 60) },
                            set: { viewModel.longBreakDuration = TimeInterval($0 * 60) }
                        ),
                        range: 15 ... 30,
                        step: 5,
                        unit: " min"
                    )

                    TideDivider()

                    settingsStepper(
                        title: "Sessions Before Long Break",
                        value: $viewModel.sessionsBeforeLongBreak,
                        range: 2 ... 6,
                        step: 1,
                        unit: ""
                    )
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
            .navigationTitle("Focus Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func settingsStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        unit: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: Tide.s2) {
                Text(title)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tide.s2)
                Text("\(value.wrappedValue)\(unit)")
                    .font(Tide.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(Tide.text2)
            }
        }
        .frame(minHeight: Tide.hit)
        .accessibilityLabel(title)
        .accessibilityValue("\(value.wrappedValue)\(unit)")
    }

    // MARK: - Helpers

    private var isPaused: Bool {
        if case .paused = viewModel.focusState {
            return true
        }
        return false
    }

    private var isReview: Bool {
        if case .review = viewModel.focusState {
            return true
        }
        return false
    }

    private var isIdleOrConfiguring: Bool {
        switch viewModel.focusState {
        case .idle,
             .configuring: true
        default: false
        }
    }

    private var isBreakState: Bool {
        switch viewModel.focusState {
        case .onBreak,
             .longBreak: true
        default: false
        }
    }

    private var elapsedMinutes: Int {
        guard let start = viewModel.currentStudySession?.startTime else {
            return 0
        }
        return Int(Date().timeIntervalSince(start) / 60)
    }

    private func handleStateChange(_ state: FocusTimerState) {
        // Per spec B16 — keep the screen lit during active focus/break states.
        UIApplication.shared.isIdleTimerDisabled = state.isActive
        switch state {
        case .sessionDone:
            HapticManager.notification(.success)
        case .breakDone:
            HapticManager.notification(.warning)
        case .completed:
            // Triple success haptic
            HapticManager.notification(.success)
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                HapticManager.notification(.success)
                try? await Task.sleep(for: .milliseconds(200))
                HapticManager.notification(.success)
            }
        case .onBreak,
             .longBreak:
            breakMessageIndex = Int.random(in: 0 ..< breakMessages.count)
        default:
            break
        }
    }

    private func startColonBlink() {
        blinkTask?.cancel()
        blinkTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                if isPaused {
                    withAnimation(Tide.snap) {
                        colonVisible.toggle()
                    }
                } else {
                    colonVisible = true
                }
            }
        }
    }
}
