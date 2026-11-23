//
// ArenaIntroView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Arena Intro View (Onboarding)

// Per STATE_MACHINES.md Section 10 — Explain XP, leaderboards, challenges. Informational.

struct ArenaIntroView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            title: "WELCOME TO\nTHE ARENA.",
            primaryTitle: "ENTER TEMPO",
            primaryAction: { viewModel.advance() },
            centered: true
        ) {
            OnboardingHeroTile(systemName: "trophy.fill", tint: Tide.carbs)

            GlassEffectContainer(spacing: Tide.s3) {
                VStack(spacing: Tide.s3) {
                    featureCard(
                        icon: "star.fill",
                        title: "EARN XP",
                        body: "Every workout, study session, and meal logged earns experience points."
                    )
                    featureCard(
                        icon: "chart.bar.fill",
                        title: "CLIMB THE RANKS",
                        body: "Compete with friends on weekly leaderboards."
                    )
                    featureCard(
                        icon: "bolt.fill",
                        title: "CHALLENGE FRIENDS",
                        body: "Head-to-head challenges to push each other harder."
                    )
                }
            }
        }
    }

    private func featureCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            TideIconTile(systemName: icon, tint: Tide.carbs, size: Tide.tile)

            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(title).tideLabel(Tide.text)
                Text(body)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ArenaIntroView(viewModel: OnboardingViewModel())
        .tidePage(energy: 1)
}
