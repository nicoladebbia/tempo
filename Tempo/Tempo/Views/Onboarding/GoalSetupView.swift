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
        // Per WIREFRAMES.md Screen 46 — "WHAT ARE YOU FIGHTING FOR?"
        OnboardingScaffold(
            title: "WHAT ARE YOU\nFIGHTING FOR?",
            primaryTitle: "CONTINUE",
            primaryEnabled: viewModel.canContinue,
            primaryAction: { viewModel.advance() }
        ) {
            // Primary goal — the goal rows are the cards.
            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("Primary goal")
                VStack(spacing: Tide.s2) {
                    ForEach(goals, id: \.0) { name, desc in
                        OnboardingOptionRow(
                            title: name,
                            subtitle: desc,
                            isSelected: viewModel.primaryGoal == name
                        ) {
                            viewModel.primaryGoal = name
                        }
                    }
                }
            }

            // Time-waster — chips flow inline.
            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("What's your biggest time-waster?")
                FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                    ForEach(timeWasterOptions, id: \.self) { option in
                        OnboardingChip(title: option, isSelected: viewModel.timeWasters.contains(option)) {
                            if viewModel.timeWasters.contains(option) {
                                viewModel.timeWasters.remove(option)
                            } else {
                                viewModel.timeWasters.insert(option)
                            }
                        }
                    }
                }
            }

            // Evening start time
            // Per WIREFRAMES.md Screen 46 — Time picker, 15min increments.
            // `.compact` style instead of `.wheel` because the wheel picker
            // has a fixed intrinsic minimum width (~320pt) that forces the
            // parent VStack to expand past the screen width, dragging every
            // sibling card off the left edge inside the vertical ScrollView.
            // (Diagnosed via border-frame visualization on 2026-05-12.)
            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("When does your evening start?")
                HStack {
                    DatePicker("", selection: $viewModel.eveningStartTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(minHeight: Tide.hit)
                    Spacer()
                }
                OnboardingNote("This is when the drill sergeant gets serious.")
            }
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    GoalSetupView(viewModel: vm)
        .tidePage(energy: 1)
}
