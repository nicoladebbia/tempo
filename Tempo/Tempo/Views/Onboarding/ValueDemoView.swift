//
// ValueDemoView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
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
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                // Header
                VStack(spacing: TempoSpacing.sm) {
                    Text("THIS IS TEMPO")
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Your entire life — training, nutrition, recovery, accountability — in one app.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, TempoSpacing.xl)

                // Sample dashboard preview cards

                // Recovery card
                sampleCard(
                    icon: "heart.fill",
                    title: "RECOVERY",
                    subtitle: "Whoop-powered daily insights",
                    value: "72%",
                    valueColor: Color.tempoAmber,
                    detail: "HRV 58ms \u{00B7} RHR 62 \u{00B7} Sleep 7.2h"
                )

                // Training card
                sampleCard(
                    icon: "dumbbell.fill",
                    title: "TRAINING",
                    subtitle: "AI-adjusted to your recovery",
                    value: "Push Day",
                    valueColor: Color.tempoSignal,
                    detail: "5 exercises \u{00B7} Est. 52 min"
                )

                // Nutrition card
                sampleCard(
                    icon: "leaf.fill",
                    title: "NUTRITION",
                    subtitle: "AI meal plans & macro tracking",
                    value: "2,450 kcal",
                    valueColor: Color.tempoSuccess,
                    detail: "P: 185g \u{00B7} C: 280g \u{00B7} F: 72g"
                )

                // Accountability card
                sampleCard(
                    icon: "lock.fill",
                    title: "ACCOUNTABILITY",
                    subtitle: "Non-negotiables & daily targets",
                    value: "3/5 done",
                    valueColor: Color.tempoAmber,
                    detail: "Train \u{00B7} Study 2h \u{00B7} Log meals"
                )

                // Consolidation pitch
                VStack(spacing: TempoSpacing.xs) {
                    Text("One app. Not five.")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Replaces your workout tracker, meal planner, sleep app, habit tracker, and study timer.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, TempoSpacing.md)

                // CTA
                Button(action: onContinue) {
                    Text("SET UP MY TEMPO")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoBgPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.tempoSignal)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg))
                }
                .padding(.top, TempoSpacing.md)

                // Skip option
                Button("Skip tour") {
                    onContinue()
                }
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.bottom, TempoSpacing.bottomSafe)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
        .background(Color.tempoBgPrimary)
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
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(valueColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .tracking(1.2)
                    Text(subtitle)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                Spacer()
                Text("SAMPLE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.tempoTextTertiary.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.tempoTitle2)
                    .foregroundStyle(valueColor)
                Spacer()
                Text(detail)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg))
    }
}
