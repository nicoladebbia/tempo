//
// OnboardingContainerView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - OnboardingContainerView

// Per BUILD_PLAN step 16.1 — PageView-style container for 11 onboarding steps.
// Per WIREFRAMES.md Screen 44 — Progress bar, dark mode, full-bleed layout.
// Per STATE_MACHINES.md Section 10 — "Show then ask" flow with back navigation and skip.

struct OnboardingContainerView: View {
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Progress: hidden during splash, valueDemo and complete.
            if showsProgress {
                progressBar
                    .padding(.top, Tide.s2)
                    .transition(.opacity)
            }

            // Step content fills the rest. Opacity-only transition: `.scale` /
            // `.move` here caused overflow artifacts on device.
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(viewModel.currentStep)
                .transition(.opacity)
        }
        // Onboarding is the one place the Tide field runs at full energy.
        .tidePage(energy: 1)
        .environment(\.tideMood, .neutral)
        .onAppear {
            viewModel.onComplete = {
                services.appState.isOnboardingComplete = true
            }
            // Auto-advance splash after 1.8s
            if viewModel.currentStep == .splash {
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    viewModel.advance()
                }
            }
        }
    }

    private var showsProgress: Bool {
        viewModel.currentStep != .splash && viewModel.currentStep != .valueDemo && viewModel.currentStep != .complete
    }

    // MARK: - Progress Bar

    // A slim Tide level bar with the back button on its left.

    private var progressBar: some View {
        HStack(spacing: Tide.s3) {
            if viewModel.canGoBack {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            TideLevelBar(progress: viewModel.progress, color: .white, height: Tide.barSlim)
                .background(Tide.fill, in: .capsule)
                .animation(Tide.snap, value: viewModel.progress)
                .accessibilityLabel("Setup progress")
        }
        .frame(minHeight: Tide.hit)
        .padding(.horizontal, Tide.edge)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .splash:
            OnboardingSplashView(viewModel: viewModel)
        case .valueDemo:
            ValueDemoView(onContinue: { viewModel.advance() })
        case .goals:
            GoalSetupView(viewModel: viewModel)
        case .healthkit:
            HealthKitPermissionView(viewModel: viewModel)
        case .auth:
            OnboardingAuthView(viewModel: viewModel)
        case .profile:
            ProfileSetupView(viewModel: viewModel)
        case .identity:
            IdentitySetupView(viewModel: viewModel)
        case .trainingSetup:
            TrainingSetupView(viewModel: viewModel)
        case .academicSetup:
            AcademicSetupView(viewModel: viewModel)
        case .dailyRhythm:
            DailyRhythmView(viewModel: viewModel)
        case .classSchedule:
            ClassScheduleView(viewModel: viewModel)
        case .eatingWindow:
            EatingWindowView(viewModel: viewModel)
        case .studyPreferences:
            StudyPreferencesView(viewModel: viewModel)
        case .trainingPreferences:
            TrainingPreferencesView(viewModel: viewModel)
        case .weekendMode:
            WeekendModeView(viewModel: viewModel)
        case .whoopConnect:
            WhoopConnectView(viewModel: viewModel)
        case .notifications:
            NotificationSetupView(viewModel: viewModel)
        case .tosAccept:
            TermsAcceptanceView(viewModel: viewModel)
        case .aiConsent:
            AIConsentView(viewModel: viewModel)
        case .complete:
            OnboardingCompleteView(viewModel: viewModel)
        }
    }
}

// MARK: - OnboardingPrimaryButton

/// The one filled button of a step. Steps built on `OnboardingScaffold` pin
/// their own; this stays for views that lay out their own footer.
struct OnboardingPrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.tidePrimary)
            .disabled(!enabled)
            .padding(.horizontal, Tide.edge)
    }
}

// MARK: - OnboardingSkipButton

struct OnboardingSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("SKIP")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text2)
                .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - OnboardingCardModifier

// A glass card for grouped content inside a step.

struct OnboardingCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        // `tideCard` is already full width: without that a card hugs its
        // content, so cards with short chip rows render narrower than siblings.
        content.tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }
}

extension View {
    func onboardingCard() -> some View {
        modifier(OnboardingCardModifier())
    }
}
