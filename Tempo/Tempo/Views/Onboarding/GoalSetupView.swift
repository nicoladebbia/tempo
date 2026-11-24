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
//
// The question is "what are you fighting for?", so the answers are big cards
// with a symbol each, not a list. The time-waster chips carry a symbol too and
// the evening start is a large time control instead of a small field.

struct GoalSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    private struct Goal: Hashable {
        let name: String
        let detail: String
        let icon: String
    }

    private struct TimeWaster: Hashable {
        let name: String
        let icon: String
    }

    private let goals = [
        Goal(name: "Build Muscle", detail: "Gain size and strength", icon: "dumbbell.fill"),
        Goal(name: "Lose Fat", detail: "Cut while keeping muscle", icon: "flame.fill"),
        Goal(name: "Improve Performance", detail: "Sport-specific gains", icon: "bolt.fill"),
        Goal(name: "Stay Healthy", detail: "Maintain and prevent", icon: "heart.fill"),
        Goal(name: "All-Around", detail: "Balance everything", icon: "circle.hexagongrid.fill"),
    ]

    private let timeWasters = [
        TimeWaster(name: "PS5/Gaming", icon: "gamecontroller.fill"),
        TimeWaster(name: "Social Media", icon: "bubble.left.and.bubble.right.fill"),
        TimeWaster(name: "Netflix/Streaming", icon: "tv.fill"),
        TimeWaster(name: "YouTube", icon: "play.rectangle.fill"),
        TimeWaster(name: "Other", icon: "ellipsis"),
    ]

    var body: some View {
        // Per WIREFRAMES.md Screen 46 — "WHAT ARE YOU FIGHTING FOR?"
        OnboardingScaffold(
            title: "WHAT ARE YOU\nFIGHTING FOR?",
            primaryTitle: "CONTINUE",
            primaryEnabled: viewModel.canContinue,
            primaryAction: { viewModel.advance() }
        ) {
            // Primary goal: one card each, the last one across the row.
            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("Primary goal")
                OnboardingChoiceGrid(items: goals) { goal in
                    OnboardingChoiceCard(
                        title: goal.name,
                        subtitle: goal.detail,
                        systemImage: goal.icon,
                        isSelected: viewModel.primaryGoal == goal.name
                    ) {
                        viewModel.primaryGoal = goal.name
                    }
                }
            }

            // Time-waster: chips flow inline, each with its own symbol.
            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("What's your biggest time-waster?")
                FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                    ForEach(timeWasters, id: \.self) { waster in
                        OnboardingChip(
                            title: waster.name,
                            systemImage: waster.icon,
                            isSelected: viewModel.timeWasters.contains(waster.name)
                        ) {
                            if viewModel.timeWasters.contains(waster.name) {
                                viewModel.timeWasters.remove(waster.name)
                            } else {
                                viewModel.timeWasters.insert(waster.name)
                            }
                        }
                    }
                }
            }

            // Evening start time
            // Per WIREFRAMES.md Screen 46 — time, 15 minute steps. A big figure
            // with a minus and a plus: no system wheel, which has a fixed
            // minimum width that once pushed every sibling off the left edge.
            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("When does your evening start?")
                OnboardingTimeControl(title: "Evening starts", systemImage: "moon.stars.fill", minutes: eveningMinutes)
                OnboardingNote("This is when the drill sergeant gets serious.")
            }
        }
    }

    /// The evening start is stored as a date; the control works in minutes.
    private var eveningMinutes: Binding<Int> {
        Binding(
            get: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: viewModel.eveningStartTime)
                return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            },
            set: { minutes in
                viewModel.eveningStartTime = Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: viewModel.eveningStartTime
                ) ?? viewModel.eveningStartTime
            }
        )
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    GoalSetupView(viewModel: vm)
        .tidePage(energy: 1)
}
