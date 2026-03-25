import SwiftUI

// MARK: - Whoop Connect View
// Per WIREFRAMES.md Screen 47 — Whoop connection during onboarding. OPTIONAL.
// Per STATE_MACHINES.md Section 10 — Connected or Skip.

struct WhoopConnectView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            // Per WIREFRAMES.md Screen 47 — "YOUR BODY TALKS. LET'S LISTEN."
            Text("YOUR BODY TALKS.\nLET'S LISTEN.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoSuccess)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                benefitRow(icon: "heart.fill", text: "Recovery scores + HRV")
                benefitRow(icon: "moon.fill", text: "Sleep analysis")
                benefitRow(icon: "flame.fill", text: "Strain tracking")
                benefitRow(icon: "arrow.triangle.2.circlepath", text: "Auto-adjusted workouts")
            }
            .padding(.horizontal, TempoSpacing.xxl)

            Spacer()

            OnboardingPrimaryButton(title: "CONNECT WHOOP", enabled: true) {
                // TODO: Trigger Whoop OAuth flow
                viewModel.whoopConnected = true
                viewModel.advance()
            }

            OnboardingSkipButton { viewModel.skip() }

            Spacer().frame(height: TempoSpacing.xxxl)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoSuccess)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
