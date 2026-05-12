//
// GoalSetupView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Goal Setup View

// Per WIREFRAMES.md Screen 46 — Goals + Non-negotiables + time-waster + evening time.
// Per STATE_MACHINES.md Section 10 — REQUIRED (primaryGoal must be set).

struct GoalSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    private let goals = [
        ("Build Muscle", "Gain size and strength"),
        ("Lose Fat", "Cut while keeping muscle"),
        ("Improve Performance", "Sport-specific gains"),
        ("Stay Healthy", "Maintain and prevent"),
        ("All-Around", "Balance everything"),
    ]

    private let timeWasterOptions = ["PS5/Gaming", "Social Media", "Netflix/Streaming", "YouTube", "Other"]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                // Per WIREFRAMES.md Screen 46 — "WHAT ARE YOU FIGHTING FOR?"
                // Match the main-app hero typography (28pt Bold per DESIGN_SYSTEM.md).
                Text("WHAT ARE YOU\nFIGHTING FOR?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Primary goal — no outer card. The goal rows are the cards.
                sectionLabel("Primary goal")
                VStack(spacing: TempoSpacing.sm) {
                    ForEach(goals, id: \.0) { name, desc in
                        Button {
                            viewModel.primaryGoal = name
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(desc)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 56)
                            .padding(.horizontal, TempoSpacing.md)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        viewModel.primaryGoal == name ? Color.tempoAmber : Color.white.opacity(0.15),
                                        lineWidth: viewModel.primaryGoal == name ? 2 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Time-waster — no outer card, chips flow inline.
                sectionLabel("What's your biggest time-waster?")
                FlowLayout(spacing: TempoSpacing.sm, lineSpacing: TempoSpacing.sm) {
                    ForEach(timeWasterOptions, id: \.self) { option in
                        Button {
                            if viewModel.timeWasters.contains(option) {
                                viewModel.timeWasters.remove(option)
                            } else {
                                viewModel.timeWasters.insert(option)
                            }
                        } label: {
                            Text(option)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(viewModel.timeWasters.contains(option) ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(viewModel.timeWasters.contains(option) ? Color.tempoAmber : Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Evening start time
                // Per WIREFRAMES.md Screen 46 — Time picker, 15min increments.
                // `.compact` style instead of `.wheel` because the wheel picker
                // has a fixed intrinsic minimum width (~320pt) that forces the
                // parent VStack to expand past the screen width, dragging every
                // sibling card off the left edge inside the vertical ScrollView.
                // (Diagnosed via border-frame visualization on 2026-05-12.)
                sectionLabel("When does your evening start?")
                HStack {
                    DatePicker("", selection: $viewModel.eveningStartTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .colorScheme(.dark)
                    Spacer()
                }
                Text("This is when the drill sergeant gets serious.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer(minLength: TempoSpacing.xl)

                OnboardingPrimaryButton(title: "CONTINUE", enabled: viewModel.canContinue) {
                    viewModel.advance()
                }

                Spacer().frame(height: TempoSpacing.sm)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    GoalSetupView(viewModel: vm)
        .background(Color.tempoBgPrimary)
        .preferredColorScheme(.dark)
}
