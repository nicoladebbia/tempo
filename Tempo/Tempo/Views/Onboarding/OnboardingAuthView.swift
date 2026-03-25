import SwiftUI
import AuthenticationServices

// MARK: - Onboarding Auth View
// Per STATE_MACHINES.md Section 10 — Sign in with Apple. REQUIRED. No skip.
// Per WIREFRAMES.md Screen 44 — Welcome + value prop + CTA

struct OnboardingAuthView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Value prop
            // Per WIREFRAMES.md Screen 44 — "STOP MANAGING YOUR LIFE IN 5 DIFFERENT APPS."
            VStack(spacing: TempoSpacing.lg) {
                Text("STOP MANAGING YOUR LIFE\nIN 5 DIFFERENT APPS.")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Training. Nutrition.\nRecovery. Academics.\nOne system. One score.\nZero excuses.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()

            // Sign in with Apple
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success:
                    viewModel.advance()
                case .failure:
                    break  // Per STATE_MACHINES.md — Stay on screen, no error shown
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, TempoSpacing.lg)

            Spacer().frame(height: TempoSpacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
