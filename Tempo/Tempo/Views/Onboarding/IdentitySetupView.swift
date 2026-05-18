//
// IdentitySetupView.swift
// Tempo
//
// Created by Tempo on 18/05/2026.
//
//

import SwiftUI

// MARK: - Identity Setup View

// "What best describes you?" — single-select identity label. REQUIRED.
// The chosen label persists to UserProfile.identityLabel (via the onboarding
// UserDefaults bridge in ContentView.ensureUserProfile) and is surfaced in
// Settings. Options are the canonical list in OnboardingViewModel.identityLabels.

struct IdentitySetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    private let labels = OnboardingViewModel.identityLabels

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: geometry.size.height * 0.12)

                Text("WHAT BEST DESCRIBES YOU?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TempoSpacing.xl)

                Spacer()
                    .frame(height: geometry.size.height * 0.05)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: TempoSpacing.sm) {
                        ForEach(labels, id: \.self) { label in
                            identityRow(label)
                        }
                    }
                    .padding(.horizontal, TempoSpacing.xl)
                    .padding(.bottom, TempoSpacing.md)
                }

                Spacer(minLength: 0)

                OnboardingPrimaryButton(
                    title: "CONTINUE",
                    enabled: viewModel.canContinue
                ) {
                    viewModel.advance()
                }

                Spacer()
                    .frame(height: max(geometry.safeAreaInsets.bottom + 20, 40))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    // Renders one selectable identity row. Tapping it sets
    // viewModel.identityLabel. The currently-selected label is visually
    // distinct (checkmark + highlighted border/background).
    @ViewBuilder
    private func identityRow(_ label: String) -> some View {
        let isSelected = viewModel.identityLabel == label

        Button {
            viewModel.identityLabel = label
            HapticManager.lightImpact()
        } label: {
            HStack(spacing: TempoSpacing.sm) {
                Text(label)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.tempoSignal)
                }
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(isSelected ? 0.16 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.tempoSignal.opacity(0.8) : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    IdentitySetupView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
