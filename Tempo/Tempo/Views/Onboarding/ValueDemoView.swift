//
// ValueDemoView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - Value Demo View

// "Show then ask" — Interactive demo showing sample dashboard data
// before collecting any personal information. Per market research (8/8 agents):
// demonstrate value within 90 seconds.

struct ValueDemoView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(
            title: "THIS IS TEMPO",
            subtitle: "Your entire life — training, nutrition, recovery, accountability — in one app.",
            primaryTitle: "SET UP MY TEMPO",
            primaryAction: onContinue,
            skipTitle: "Skip tour",
            skipAction: onContinue
        ) {
            GlassEffectContainer(spacing: Tide.s3) {
                VStack(spacing: Tide.s3) {
                    sampleCard(
                        icon: "heart.fill",
                        title: "RECOVERY",
                        subtitle: "Whoop-powered daily insights",
                        value: "72%",
                        valueColor: Tide.protein,
                        detail: "HRV 58ms \u{00B7} RHR 62 \u{00B7} Sleep 7.2h"
                    )

                    sampleCard(
                        icon: "dumbbell.fill",
                        title: "TRAINING",
                        subtitle: "AI-adjusted to your recovery",
                        value: "Push Day",
                        valueColor: Tide.fat,
                        detail: "5 exercises \u{00B7} Est. 52 min"
                    )

                    sampleCard(
                        icon: "leaf.fill",
                        title: "NUTRITION",
                        subtitle: "AI meal plans & macro tracking",
                        value: "2,450 kcal",
                        valueColor: Color.tempoSuccess,
                        detail: "P: 185g \u{00B7} C: 280g \u{00B7} F: 72g"
                    )

                    sampleCard(
                        icon: "lock.fill",
                        title: "ACCOUNTABILITY",
                        subtitle: "Non-negotiables & daily targets",
                        value: "3/5 done",
                        valueColor: Tide.carbs,
                        detail: "Train \u{00B7} Study 2h \u{00B7} Log meals"
                    )
                }
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
    }

    // MARK: - Sample Card

    private func sampleCard(
        icon: String,
        title: String,
        subtitle: String,
        value: String,
        valueColor: Color,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s3) {
                TideIconTile(systemName: icon, tint: valueColor, size: Tide.tile)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(title).tideLabel()
                    Text(subtitle)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                Spacer(minLength: Tide.s2)
                Text("SAMPLE")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text2)
                    .padding(.horizontal, Tide.s2)
                    .padding(.vertical, Tide.hair)
                    .background(Tide.fill, in: .capsule)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(Tide.numeral(Tide.numeralS + Tide.s2))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                Spacer(minLength: Tide.s2)
                Text(detail)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ValueDemoView(onContinue: {})
        .tidePage(energy: 1)
}
