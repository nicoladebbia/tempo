//
// HealthKitPermissionView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - HealthKit Permission View (Onboarding)

// Per STATE_MACHINES.md Section 10 — Request HealthKit permissions. OPTIONAL.
//
// The step shows what the permission buys: a small "Health today" board with
// the four things Tempo reads, filled with sample numbers.

struct HealthKitPermissionView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var filled = false

    private struct Reading: Hashable {
        let icon: String
        let value: String
        var unit: String?
        let progress: Double
        let caption: String
    }

    private let readings = [
        Reading(icon: "figure.walk", value: "8,420", unit: "steps", progress: 0.84, caption: "Steps & active calories"),
        Reading(icon: "heart.fill", value: "62", unit: "bpm", progress: 0.5, caption: "Heart rate data"),
        Reading(icon: "bed.double.fill", value: "7.2", unit: "h", progress: 0.9, caption: "Sleep tracking"),
        Reading(icon: "flame.fill", value: "540", unit: "kcal", progress: 0.7, caption: "Workout integration"),
    ]

    var body: some View {
        OnboardingScaffold(
            title: "LET'S CONNECT\nYOUR HEALTH DATA.",
            primaryTitle: "ALLOW HEALTHKIT",
            primaryAction: {
                Task {
                    try? await services.healthKit.requestAuthorization()
                    viewModel.healthkitGranted = true
                    viewModel.advance()
                }
            },
            skipAction: { viewModel.skip() },
            centered: true
        ) {
            OnboardingPreviewFrame(title: "Health today") {
                OnboardingChoiceGrid(items: readings) { reading in
                    OnboardingMetricTile(
                        systemImage: reading.icon,
                        value: reading.value,
                        unit: reading.unit,
                        progress: reading.progress,
                        caption: reading.caption,
                        tint: Tide.protein,
                        filled: filled
                    )
                }
            }

            OnboardingNote(
                "Your health data stays on your device. Tempo never uploads raw HealthKit data.",
                systemImage: "lock.fill"
            )
        }
        .task {
            if reduceMotion {
                filled = true
            } else {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(Tide.settle) { filled = true }
            }
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    HealthKitPermissionView(viewModel: vm)
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
