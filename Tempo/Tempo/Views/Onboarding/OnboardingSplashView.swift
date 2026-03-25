import SwiftUI

// MARK: - Onboarding Splash View
// Per STATE_MACHINES.md Section 10 — Animated splash, 1.8s, auto-advances.

struct OnboardingSplashView: View {
    let viewModel: OnboardingViewModel
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.8

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.tempoAmber)
                .scaleEffect(scale)
                .opacity(opacity)

            Text("TEMPO")
                .font(.system(size: 36, weight: .black))
                .tracking(4)
                .foregroundStyle(.white)
                .opacity(opacity)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                opacity = 1
                scale = 1
            }
        }
    }
}
