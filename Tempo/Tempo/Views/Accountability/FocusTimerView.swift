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
            // Background
            Color.tempoBgPrimary
                .ignoresSafeArea()

            // Phase-tinted background
            phaseBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation bar
                navigationBar
                    .padding(.horizontal, TempoSpacing.screenEdge)

                // Smart recommendation banner
                if case .idle = viewModel.focusState {
                    focusRecommendationBanner
                        .padding(.horizontal, TempoSpacing.screenEdge)
                        .padding(.top, TempoSpacing.sm)
                } else if case .configuring = viewModel.focusState {
                    focusRecommendationBanner
                        .padding(.horizontal, TempoSpacing.screenEdge)
                        .padding(.top, TempoSpacing.sm)
                }

                Spacer()

                // Session label
                sessionLabel
                    .padding(.bottom, TempoSpacing.sm)

                // Subject pill
                if let subject = viewModel.focusSubject {
                    subjectPill(subject)
                        .padding(.bottom, TempoSpacing.lg)
                }

                // Timer ring
                timerRing
                    .padding(.bottom, TempoSpacing.sm)

                // Phase label
                phaseLabel
                    .padding(.bottom, TempoSpacing.md)

                // Accumulated time
                accumulatedTime
                    .padding(.bottom, TempoSpacing.xs)

                // Focus score (only during focusing)
                if case .focusing = viewModel.focusState {
                    focusScoreDisplay
                        .padding(.bottom, TempoSpacing.lg)
                } else {
                    Spacer().frame(height: TempoSpacing.lg)
                }

                // Break message
                if isBreakState {
                    breakMessageView
                        .padding(.bottom, TempoSpacing.lg)
                }

                Spacer()

                // Secondary buttons (distraction + ambient)
                if viewModel.focusState.isActive {
                    secondaryButtons
                        .padding(.horizontal, TempoSpacing.screenEdge)
                        .padding(.bottom, TempoSpacing.lg)
                }

                // Primary controls
                primaryControls
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.bottom, TempoSpacing.bottomSafe)
            }

            // Completion overlay
            if case let .completed(totalSessions) = viewModel.focusState {
                completionOverlay(totalSessions: totalSessions)
            }

            // Review overlay
            if case .review = viewModel.focusState {
                reviewOverlay
            }
        }
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

    // MARK: - Smart Focus Recommendation Banner

    // Shows context-aware timer recommendation based on study progress today.

    private var focusRecommendationBanner: some View {
        let recommendation = focusRecommendation

        return HStack(spacing: TempoSpacing.sm) {
            Image(systemName: recommendation.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(recommendation.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(recommendation.title)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text(recommendation.subtitle)
                    .font(.tempoFootnote)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()

            if let suggestedMinutes = recommendation.suggestedDuration {
                Button {
                    viewModel.focusDuration = TimeInterval(suggestedMinutes * 60)
                    HapticManager.impact(.light)
                } label: {
                    Text("\(suggestedMinutes)m")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, TempoSpacing.md)
                        .frame(height: 28)
                        .background(recommendation.color)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                }
            }
        }
        .padding(TempoSpacing.md)
        .background(recommendation.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                .stroke(recommendation.color.opacity(0.25), lineWidth: 1)
        )
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
                color: .tempoSuccess,
                suggestedDuration: 25
            )
        }

        // Very close to target (15 min or less)
        if remaining <= 15 {
            return FocusRecommendation(
                title: "Just \(remaining)m left. Finish strong.",
                subtitle: "One short sprint to complete your study goal.",
                icon: "flag.checkered",
                color: .tempoSuccess,
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
                    title: "\(remaining)m needed. Only \(Int(timeToPS5 / 60))m until PS5 time.",
                    subtitle: "Start NOW. Every minute counts.",
                    icon: "exclamationmark.triangle.fill",
                    color: .tempoSignal,
                    suggestedDuration: min(remaining, 50)
                )
            }

            return FocusRecommendation(
                title: "You need \(remaining)m today. Let's go.",
                subtitle: subtitle,
                icon: "play.circle.fill",
                color: .tempoElectric,
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
                subtitle: "Less than \(Int(timeToPS5 / 60))m until PS5 time. Buckle down.",
                icon: "exclamationmark.triangle.fill",
                color: .tempoAmber,
                suggestedDuration: min(remaining, 50)
            )
        }

        return FocusRecommendation(
            title: "\(remaining)m remaining. Time for \(suggestedDuration >= 45 ? "a deep work session" : "a sprint").",
            subtitle: "\(totalMinutes)m done so far. Keep the momentum.",
            icon: "bolt.fill",
            color: .tempoElectric,
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Session Label

    private var sessionLabel: some View {
        Group {
            if viewModel.currentSessionCount >= viewModel.sessionsBeforeLongBreak {
                Text("Bonus Session")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoAmber)
            } else {
                Text("Session \(viewModel.currentSessionCount + 1) of \(viewModel.sessionsBeforeLongBreak)")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
    }

    // MARK: - Subject Pill

    private func subjectPill(_ subject: String) -> some View {
        Button {
            showSubjectPicker = true
        } label: {
            HStack(spacing: TempoSpacing.sm) {
                Text(subject)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(.horizontal, TempoSpacing.md)
            .frame(height: 32)
            .background(Color.tempoSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 1)
            )
        }
        .sheet(isPresented: $showSubjectPicker) {
            subjectPickerSheet
        }
    }

    // MARK: - Subject Picker

    private static let studySubjects = [
        "Math", "CS", "Languages", "Physics", "Chemistry",
        "Biology", "History", "Literature", "Economics", "Engineering",
    ]

    private var subjectPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(Self.studySubjects, id: \.self) { subject in
                    Button {
                        viewModel.focusSubject = subject
                        viewModel.currentStudySession?.subject = subject
                        showSubjectPicker = false
                    } label: {
                        HStack {
                            Text(subject)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            if viewModel.focusSubject == subject {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.tempoElectric)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Study Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSubjectPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Timer Ring

    // Per MODULE_ACCOUNTABILITY.md — 260pt ring, 8pt stroke.

    private var timerRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.tempoBorder, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 260, height: 260)

            // Fill
            Circle()
                .trim(from: 0, to: viewModel.focusTimerProgress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 260, height: 260)
                .animation(.linear(duration: 1), value: viewModel.focusTimerProgress)

            // Timer display
            timerText
        }
    }

    private var timerText: some View {
        let parts = viewModel.formattedFocusTimer.split(separator: ":")
        let minutes = parts.first ?? "0"
        let seconds = parts.count > 1 ? parts[1] : "00"

        return HStack(spacing: 0) {
            Text(String(minutes))
                .font(.tempoTimerDisplay)
                .foregroundStyle(Color.tempoTextPrimary)
                .monospacedDigit()

            Text(":")
                .font(.tempoTimerDisplay)
                .foregroundStyle(Color.tempoTextPrimary)
                .opacity(isPaused ? (colonVisible ? 1 : 0.3) : 1)

            Text(String(seconds))
                .font(.tempoTimerDisplay)
                .foregroundStyle(Color.tempoTextPrimary)
                .monospacedDigit()
        }
    }

    private var ringColor: Color {
        if isPaused {
            return .tempoAmber
        }
        if isBreakState {
            return .tempoSuccess
        }
        return .tempoElectric
    }

    // MARK: - Phase Label

    // Per MODULE_ACCOUNTABILITY.md — phase label below ring.

    private var phaseLabel: some View {
        Text(phaseLabelText)
            .font(.tempoZoneLabel)
            .tracking(TempoTracking.zoneLabel)
            .foregroundStyle(phaseLabelColor)
    }

    private var phaseLabelText: String {
        switch viewModel.focusState {
        case .idle,
             .configuring: "READY"
        case .focusing: "FOCUS TIME"
        case .onBreak,
             .longBreak: "BREAK TIME"
        case .paused: "PAUSED"
        case .sessionDone: "SESSION DONE"
        case .breakDone: "BREAK DONE"
        case .completed: "COMPLETE"
        case .review: "REVIEW"
        case .cancelled: "CANCELLED"
        }
    }

    private var phaseLabelColor: Color {
        switch viewModel.focusState {
        case .focusing: .tempoElectric
        case .onBreak,
             .longBreak,
             .breakDone: .tempoSuccess
        case .paused: .tempoAmber
        case .completed: .tempoSuccess
        default: .tempoTextSecondary
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

        return Text("Today's total: \(currentText) / \(targetText)")
            .font(.tempoCallout)
            .foregroundStyle(Color.tempoTextSecondary)
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
            .font(.tempoCallout)
            .foregroundStyle(Color.tempoTextPrimary)
    }

    // MARK: - Break Message

    private var breakMessageView: some View {
        Text(breakMessages[breakMessageIndex % breakMessages.count])
            .font(.tempoBody)
            .foregroundStyle(Color.tempoTextSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, TempoSpacing.xxxl)
    }

    // MARK: - Secondary Buttons

    private var secondaryButtons: some View {
        HStack {
            // Distraction button
            Button {
                HapticManager.impact(.light)
                viewModel.distractionCount += 1
            } label: {
                VStack(spacing: TempoSpacing.xs) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.tempoTextSecondary)

                        if viewModel.distractionCount > 0 {
                            Text("\(viewModel.distractionCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Color.tempoSignal)
                                .clipShape(Circle())
                                .offset(x: 6, y: -6)
                        }
                    }

                    Text("Distracted")
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }

            Spacer()

            // Ambient button (placeholder)
            Button {
                HapticManager.impact(.light)
            } label: {
                VStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.tempoTextSecondary)

                    Text("Ambient")
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
    }

    // MARK: - Primary Controls

    // Per MODULE_ACCOUNTABILITY.md — Stop (48pt), Main (160x64pt), Skip (48pt).

    private var primaryControls: some View {
        HStack(spacing: TempoSpacing.md) {
            // Stop button
            if viewModel.focusState.isActive || isPaused {
                Button {
                    HapticManager.impact(.light)
                    showStopConfirmation = true
                } label: {
                    Image(systemName: isPaused ? "xmark.circle" : "square.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.tempoTextPrimary)
                        .frame(width: 48, height: 48)
                        .background(Color.tempoSurfaceElevated)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color.tempoBorder, lineWidth: 1)
                        )
                }
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
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isBreakState ? .white : Color.tempoTextPrimary)
                        .frame(width: 48, height: 48)
                        .background(isBreakState ? Color.tempoSuccess : Color.tempoSurfaceElevated)
                        .clipShape(Circle())
                        .overlay(
                            isBreakState
                                ? nil
                                : Circle().stroke(Color.tempoBorder, lineWidth: 1)
                        )
                }
                .accessibilityLabel("Skip")
            }
        }
    }

    private var mainButton: some View {
        Button {
            HapticManager.impact(.heavy)
            mainButtonAction()
        } label: {
            Text(mainButtonTitle)
                .font(.tempoHeadline)
                .foregroundStyle(mainButtonTextColor)
                .frame(width: 160, height: 64)
                .background(mainButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                .overlay(mainButtonBorder)
        }
    }

    private var mainButtonTitle: String {
        switch viewModel.focusState {
        case .idle,
             .configuring: "START"
        case .focusing: "PAUSE"
        case .paused: "RESUME"
        case .onBreak,
             .longBreak: "SKIP BREAK"
        case .sessionDone: "START BREAK"
        case .breakDone: "START FOCUS"
        case .completed: "REVIEW"
        case .review: "DONE"
        case .cancelled: "START"
        }
    }

    private var mainButtonTextColor: Color {
        if isBreakState {
            return .tempoSuccess
        }
        return .white
    }

    @ViewBuilder
    private var mainButtonBackground: some View {
        if isBreakState {
            Color.clear
        } else {
            Color.tempoElectric
        }
    }

    @ViewBuilder
    private var mainButtonBorder: some View {
        if isBreakState {
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoSuccess, lineWidth: 2)
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
            Color.tempoInk.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: TempoSpacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(Color.tempoSuccess)

                Text("All Sessions Complete!")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("\(totalSessions) sessions of focused study")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)

                Button {
                    viewModel.focusState = .review
                } label: {
                    Text("DONE")
                        .font(.tempoHeadline)
                        .foregroundStyle(.white)
                        .frame(width: 160, height: 52)
                        .background(Color.tempoElectric)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }
                .padding(.top, TempoSpacing.lg)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Review Overlay

    private var reviewOverlay: some View {
        ZStack {
            Color.tempoBgPrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: TempoSpacing.lg) {
                    Text("Session Review")
                        .font(.tempoTitle1)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .padding(.top, TempoSpacing.xxxl)

                    // Focus score ring
                    let score = max(0, 100 - (viewModel.distractionCount * 10))
                    CircularRingView(
                        progress: Double(score) / 100.0,
                        color: scoreColor(score),
                        ringSize: .large,
                        label: scoreLabel(score),
                        valueText: "\(score)"
                    )

                    // Stats cards
                    VStack(spacing: TempoSpacing.md) {
                        reviewStatCard(
                            title: "Total Focus Time",
                            value: "\(viewModel.currentSessionCount * Int(viewModel.focusDuration / 60))m",
                            icon: "clock.fill"
                        )

                        reviewStatCard(
                            title: "Sessions Completed",
                            value: "\(viewModel.currentSessionCount)",
                            icon: "checkmark.circle.fill"
                        )

                        reviewStatCard(
                            title: "Distractions",
                            value: "\(viewModel.distractionCount)",
                            icon: "hand.raised.fill"
                        )
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)

                    // Done button
                    Button {
                        viewModel.finishFocusReview(modelContext: modelContext)
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(.tempoHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.tempoElectric)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.top, TempoSpacing.lg)
                    .padding(.bottom, TempoSpacing.bottomSafe)
                }
            }
        }
    }

    private func reviewStatCard(title: String, value: String, icon: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.tempoElectric)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(title)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)

                Text(value)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            Spacer()
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 {
            return .tempoSuccess
        }
        if score >= 75 {
            return .tempoElectric
        }
        if score >= 50 {
            return .tempoAmber
        }
        return .tempoSignal
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
                RadialGradient(
                    colors: [Color.tempoElectric.opacity(0.03), .clear],
                    center: .center,
                    startRadius: 50,
                    endRadius: 300
                )
            case .onBreak,
                 .longBreak:
                RadialGradient(
                    colors: [Color.tempoSuccess.opacity(0.03), .clear],
                    center: .center,
                    startRadius: 50,
                    endRadius: 300
                )
            case .paused:
                RadialGradient(
                    colors: [Color.tempoAmber.opacity(0.03), .clear],
                    center: .center,
                    startRadius: 50,
                    endRadius: 300
                )
            default:
                Color.clear
            }
        }
    }

    // MARK: - Settings Sheet

    private var focusSettingsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(
                        value: Binding(
                            get: { Int(viewModel.focusDuration / 60) },
                            set: { viewModel.focusDuration = TimeInterval($0 * 60) }
                        ),
                        in: 15 ... 60,
                        step: 5
                    ) {
                        HStack {
                            Text("Focus Duration")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            Text("\(Int(viewModel.focusDuration / 60)) min")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }

                    Stepper(
                        value: Binding(
                            get: { Int(viewModel.breakDuration / 60) },
                            set: { viewModel.breakDuration = TimeInterval($0 * 60) }
                        ),
                        in: 3 ... 15,
                        step: 1
                    ) {
                        HStack {
                            Text("Short Break")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            Text("\(Int(viewModel.breakDuration / 60)) min")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }

                    Stepper(
                        value: Binding(
                            get: { Int(viewModel.longBreakDuration / 60) },
                            set: { viewModel.longBreakDuration = TimeInterval($0 * 60) }
                        ),
                        in: 15 ... 30,
                        step: 5
                    ) {
                        HStack {
                            Text("Long Break")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            Text("\(Int(viewModel.longBreakDuration / 60)) min")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }

                    Stepper(
                        value: $viewModel.sessionsBeforeLongBreak,
                        in: 2 ... 6,
                        step: 1
                    ) {
                        HStack {
                            Text("Sessions Before Long Break")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            Text("\(viewModel.sessionsBeforeLongBreak)")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                } header: {
                    Text("TIMER")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Focus Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var isPaused: Bool {
        if case .paused = viewModel.focusState {
            return true
        }
        return false
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
                    withAnimation(.easeInOut(duration: 0.3)) {
                        colonVisible.toggle()
                    }
                } else {
                    colonVisible = true
                }
            }
        }
    }
}
