//
// AcademicSetupView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Academic Setup View

// Per STATE_MACHINES.md Section 10 — Academic profile. OPTIONAL.
// Per BUILD_PLAN step 16.1 — Exam schedule, study targets.

struct AcademicSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    private let years = ["1st Year", "2nd Year", "3rd Year", "4th Year", "Postgrad", "Not in school"]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                Spacer().frame(height: TempoSpacing.md)

                Text("YOUR ACADEMICS.")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TempoSpacing.lg)

                // University
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text("University / School")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    TextField("Your school", text: $viewModel.university)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(TempoSpacing.sm)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .padding(.horizontal, TempoSpacing.lg)

                // Year of study
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text("Year of Study")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)

                    ForEach(years, id: \.self) { year in
                        Button {
                            viewModel.yearOfStudy = year
                        } label: {
                            HStack {
                                Text(year)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                if viewModel.yearOfStudy == year {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.tempoAmber)
                                }
                            }
                            .padding(TempoSpacing.md)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        viewModel.yearOfStudy == year ? Color.tempoAmber : Color.white.opacity(0.15),
                                        lineWidth: viewModel.yearOfStudy == year ? 2 : 1
                                    )
                            )
                        }
                    }
                }
                .onboardingCard()
                .padding(.horizontal, TempoSpacing.lg)

                Spacer()

                HStack {
                    OnboardingSkipButton { viewModel.skip() }
                    Spacer()
                }
                .padding(.horizontal, TempoSpacing.lg)

                OnboardingPrimaryButton(title: "CONTINUE", enabled: true) {
                    viewModel.advance()
                }

                Spacer().frame(height: TempoSpacing.lg)
            }
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    AcademicSetupView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
