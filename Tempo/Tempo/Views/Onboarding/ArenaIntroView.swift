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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: geometry.size.height * 0.1)

                Text("WELCOME TO\nTHE ARENA.")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.xl)

                Spacer()
                    .frame(height: geometry.size.height * 0.05)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(Color.tempoAmber)

                Spacer()
                    .frame(height: geometry.size.height * 0.06)

                VStack(spacing: TempoSpacing.lg) {
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
                .padding(.horizontal, TempoSpacing.xl)

                Spacer()

                OnboardingPrimaryButton(title: "ENTER TEMPO", enabled: true) {
                    viewModel.advance()
                }

                Spacer()
                    .frame(height: max(geometry.safeAreaInsets.bottom + 20, 40))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func featureCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.tempoAmber)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                Text(body)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.md)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview {
    ArenaIntroView(viewModel: OnboardingViewModel())
        .background(Color.black)
        .preferredColorScheme(.dark)
}
