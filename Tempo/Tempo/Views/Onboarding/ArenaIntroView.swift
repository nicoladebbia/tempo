import SwiftUI

// MARK: - Arena Intro View (Onboarding)
// Per STATE_MACHINES.md Section 10 — Explain XP, leaderboards, challenges. Informational.

struct ArenaIntroView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Text("WELCOME TO\nTHE ARENA.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoAmber)

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
            .padding(.horizontal, TempoSpacing.lg)

            Spacer()

            OnboardingPrimaryButton(title: "ENTER TEMPO", enabled: true) {
                viewModel.advance()
            }

            Spacer().frame(height: TempoSpacing.xxxl)
        }
    }

    private func featureCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.tempoAmber)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                Text(body)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingCard()
    }
}
