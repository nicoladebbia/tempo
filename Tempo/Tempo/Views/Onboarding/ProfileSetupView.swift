import SwiftUI

// MARK: - Profile Setup View
// Per STATE_MACHINES.md Section 10 — Display name, username. REQUIRED.
// Per BUILD_PLAN step 16.1 — Name, weight, height.

struct ProfileSetupView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.xxl) {
                Spacer().frame(height: TempoSpacing.lg)

                Text("WHO ARE YOU?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TempoSpacing.lg)

                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text("Display Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    TextField("Your name", text: $viewModel.displayName)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .padding(TempoSpacing.md)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .padding(.horizontal, TempoSpacing.lg)

                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text("Username")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    TextField("@username", text: $viewModel.username)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(TempoSpacing.md)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .padding(.horizontal, TempoSpacing.lg)

                Spacer()

                OnboardingPrimaryButton(
                    title: "CONTINUE",
                    enabled: viewModel.canContinue
                ) {
                    viewModel.advance()
                }

                Spacer().frame(height: TempoSpacing.lg)
            }
        }
    }
}
