import SwiftUI
import UserNotifications

// MARK: - Notification Setup View (Onboarding)
// Per STATE_MACHINES.md Section 10 — Request notification permissions. OPTIONAL (strongly encouraged).
// Per BUILD_PLAN step 16.1 — Permission request + intensity selection.

struct NotificationSetupView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Text("THE DRILL SERGEANT\nNEEDS YOUR ATTENTION.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoAmber)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                benefitRow(icon: "sunrise.fill", text: "Morning briefings")
                benefitRow(icon: "clock.fill", text: "Accountability check-ins")
                benefitRow(icon: "flame.fill", text: "Streak protection alerts")
                benefitRow(icon: "trophy.fill", text: "Achievement celebrations")
            }
            .padding(.horizontal, TempoSpacing.xxl)

            Text("You control exactly what and when.\nAdjust anytime in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Spacer()

            OnboardingPrimaryButton(title: "ENABLE NOTIFICATIONS", enabled: true) {
                Task {
                    let center = UNUserNotificationCenter.current()
                    let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
                    viewModel.notificationsGranted = granted ?? false
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
                .foregroundStyle(Color.tempoAmber)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
