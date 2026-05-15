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
        ZStack {
            // Onboarding follows the main app's bg token so the transition into
            // the dashboard isn't a visual jump from pure black to grey-black.
            Color.tempoBgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar — hidden during splash, valueDemo, and complete
                if viewModel.currentStep != .splash, viewModel.currentStep != .valueDemo, viewModel.currentStep != .complete {
                    progressBar
                        .padding(.top, TempoSpacing.md)
                }

                // Step content — fills remaining space. Opacity-only transition
                // avoids the mid-animation clipping artifact that `.move(edge:)`
                // produces inside a constrained safe-area frame.
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .preferredColorScheme(.dark)
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

    // MARK: - Progress Bar

    // Per WIREFRAMES.md Screen 44 — 3pt height, white fill, 20% white unfill

    private var progressBar: some View {
        HStack(spacing: TempoSpacing.sm) {
            // Back button (if applicable)
            if viewModel.canGoBack {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: geo.size.width * viewModel.progress, height: 3)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.sm)
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

struct OnboardingPrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? .black : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(enabled ? Color.tempoAmber : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!enabled)
        .padding(.horizontal, TempoSpacing.xl)
    }
}

// MARK: - OnboardingSkipButton

struct OnboardingSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("SKIP")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - OnboardingCardModifier

// Per WIREFRAMES.md Screen 44-48 — 10% white bg, 1pt 15% white border, radius 16pt

struct OnboardingCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(TempoSpacing.lg)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}

extension View {
    func onboardingCard() -> some View {
        modifier(OnboardingCardModifier())
    }
}
