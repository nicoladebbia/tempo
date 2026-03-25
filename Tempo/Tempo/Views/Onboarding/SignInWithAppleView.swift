import SwiftUI
import AuthenticationServices

// MARK: - Sign In with Apple View
// Per BUILD_PLAN step 6.5 — Sign in with Apple button using AuthenticationServices.

struct SignInWithAppleView: View {
    @Environment(ServiceContainer.self) private var services
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: TempoSpacing.xl) {
            Spacer()

            // App logo and title
            VStack(spacing: TempoSpacing.md) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.tempoSignal)

                Text("TEMPO")
                    .font(.tempoLargeTitle)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("Your Life Operating System")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.lg)
            }

            // Sign in button
            if isSigningIn {
                ProgressView()
                    .tint(Color.tempoTextSecondary)
                    .padding(.bottom, TempoSpacing.xl)
            } else {
                SignInWithAppleButton(.signIn, onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                }, onCompletion: { _ in
                    // Handled by AuthService delegate — this callback is not used
                    // because AuthService drives the flow directly
                })
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl))
                .padding(.horizontal, TempoSpacing.xl)
                .padding(.bottom, TempoSpacing.xl)
                .accessibilityLabel("Sign in with Apple")
                .onTapGesture {
                    Task { await signIn() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tempoBgPrimary)
    }

    private func signIn() async {
        isSigningIn = true
        errorMessage = nil

        do {
            try await services.authService.signInWithApple()
        } catch AuthService.AuthError.signInCancelled {
            // User cancelled — no error to show
        } catch {
            errorMessage = "Sign in failed. Please try again."
        }

        isSigningIn = false
    }
}
