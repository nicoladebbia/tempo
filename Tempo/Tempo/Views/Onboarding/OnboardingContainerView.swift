//
// OnboardingContainerView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - OnboardingContainerView

// Six steps: hook, goal, sign in, about you, permissions, ready.
// Per WIREFRAMES.md Screen 44 — Progress bar, dark mode, full-bleed layout.
// Per STATE_MACHINES.md Section 10 — "Show then ask" flow with back navigation.

struct OnboardingContainerView: View {
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var viewModel = OnboardingViewModel()
    @ScaledMetric(relativeTo: .footnote)
    private var counterSize: CGFloat = 13

    var body: some View {
        VStack(spacing: 0) {
            // Progress: hidden on the hook and on the last screen.
            if let position = viewModel.currentStep.progressPosition {
                progressBar(position: position)
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
        // The field warms to "on pace" for the last screen: you are in.
        .environment(\.tideMood, viewModel.currentStep == .complete ? TideMood(level: .onPace) : .neutral)
        .onAppear {
            viewModel.onComplete = {
                services.appState.isOnboardingComplete = true
            }
        }
    }

    // MARK: - Progress Bar

    // A slim Tide level bar with the back button on its left.

    private func progressBar(position: Int) -> some View {
        let total = viewModel.progressSteps.count
        return HStack(spacing: Tide.s3) {
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

            TideLevelBar(progress: Double(position) / Double(max(total, 1)), height: Tide.barSlim)
                .background(Tide.fill, in: .capsule)
                .animation(Tide.settle, value: position)
                .accessibilityLabel("Setup progress")

            HStack(spacing: 0) {
                Text("\(position)")
                    .font(Tide.numeral(counterSize, .bold))
                    .foregroundStyle(Tide.text)
                    .contentTransition(.numericText())
                    .animation(Tide.snap, value: position)
                Text(" / \(total)")
                    .font(Tide.numeral(counterSize, .medium))
                    .foregroundStyle(Tide.text3)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(position) of \(total)")
        }
        .frame(minHeight: Tide.hit)
        .padding(.horizontal, Tide.edge)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .valueDemo:
            ValueDemoView(onContinue: { viewModel.advance() })
        case .goals:
            GoalSetupView(viewModel: viewModel)
        case .auth:
            OnboardingAuthView(viewModel: viewModel)
        case .aboutYou:
            ProfileSetupView(viewModel: viewModel)
        case .permissions:
            PermissionsSetupView(viewModel: viewModel)
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
