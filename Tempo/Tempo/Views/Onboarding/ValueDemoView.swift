//
// ValueDemoView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - ValueDemoView

// The hook: a sample day score that lights up, and the four things Tempo
// tracks as live tiles. Everything on this page is sample data and says so.

struct ValueDemoView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var filled = false

    private struct Sample: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String
        var unit: String?
        let color: Color
        let progress: Double
        let detail: String
    }

    private let samples: [Sample] = [
        Sample(
            id: "recovery", icon: "heart.fill", title: "RECOVERY", value: "72", unit: "%",
            color: Tide.protein, progress: 0.72, detail: "HRV 58 ms \u{00B7} Sleep 7.2 h"
        ),
        Sample(
            id: "training", icon: "dumbbell.fill", title: "TRAINING", value: "Push Day",
            color: Tide.fat, progress: 0.4, detail: "2 of 5 lifts done"
        ),
        Sample(
            id: "nutrition", icon: "leaf.fill", title: "NUTRITION", value: "1,840", unit: "kcal",
            color: Color.tempoSuccess, progress: 0.75, detail: "of 2,450 kcal today"
        ),
        Sample(
            id: "accountability", icon: "lock.fill", title: "NON-NEGOTIABLES", value: "3/5", unit: "done",
            color: Tide.carbs, progress: 0.6, detail: "Train \u{00B7} Study \u{00B7} Meals"
        ),
    ]

    var body: some View {
        OnboardingScaffold(
            title: "THIS IS TEMPO",
            subtitle: "Your entire life \u{2014} training, nutrition, recovery, accountability \u{2014} in one app.",
            primaryTitle: "SET UP MY TEMPO",
            primaryAction: onContinue,
            skipTitle: "Skip tour",
            skipAction: onContinue,
            centered: true
        ) {
            TideDial(score: 72, caption: "Sample", diameter: Tide.dialSheet)

            VStack(spacing: Tide.s3) {
                GlassEffectContainer(spacing: Tide.s3) {
                    Grid(horizontalSpacing: Tide.s3, verticalSpacing: Tide.s3) {
                        GridRow {
                            sampleTile(samples[0])
                            sampleTile(samples[1])
                        }
                        GridRow {
                            sampleTile(samples[2])
                            sampleTile(samples[3])
                        }
                    }
                }
                OnboardingNote("Sample data. Yours fills in as you use Tempo.", systemImage: "info.circle")
            }

            // Consolidation pitch
            VStack(spacing: Tide.s1) {
                Text("One app. Not five.")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Text("Replaces your workout tracker, meal planner, sleep app, habit tracker, and study timer.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if reduceMotion {
                filled = true
            } else {
                withAnimation(Tide.settle.delay(0.35)) { filled = true }
            }
        }
    }

    // MARK: - Sample Tile

    private func sampleTile(_ sample: Sample) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(spacing: Tide.s2) {
                Image(systemName: sample.icon)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(sample.color)
                    .accessibilityHidden(true)
                Text(sample.title)
                    .tideLabel()
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }

            TideNumber(
                sample.value, unit: sample.unit, size: Tide.numeralS + Tide.s2,
                relativeTo: .title2, color: sample.color
            )

            TideLevelBar(progress: filled ? sample.progress : 0, color: sample.color, height: Tide.barSlim)
                .background(Tide.fill, in: .capsule)
                .accessibilityHidden(true)

            Text(sample.detail)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ValueDemoView(onContinue: {})
        .tidePage(energy: 1)
}
