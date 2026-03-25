import SwiftUI

// MARK: - HealthKit Permission View (Onboarding)
// Per STATE_MACHINES.md Section 10 — Request HealthKit permissions. OPTIONAL.

struct HealthKitPermissionView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self) private var services

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Text("LET'S CONNECT\nYOUR HEALTH DATA.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoError)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                benefitRow(icon: "figure.walk", text: "Steps & active calories")
                benefitRow(icon: "heart.fill", text: "Heart rate data")
                benefitRow(icon: "bed.double.fill", text: "Sleep tracking")
                benefitRow(icon: "flame.fill", text: "Workout integration")
            }
            .padding(.horizontal, TempoSpacing.xxl)

            Text("Your health data stays on your device.\nTempo never uploads raw HealthKit data.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Spacer()

            OnboardingPrimaryButton(title: "ALLOW HEALTHKIT", enabled: true) {
                Task {
                    try? await services.healthKit.requestAuthorization()
                    viewModel.healthkitGranted = true
                    viewModel.advance()
                }
            }

            OnboardingSkipButton { viewModel.skip() }

            Spacer().frame(height: TempoSpacing.xxxl)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoError)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
