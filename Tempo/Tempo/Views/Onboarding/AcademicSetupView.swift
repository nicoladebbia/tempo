//
// AcademicSetupView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - AcademicSetupView

// Per STATE_MACHINES.md Section 10 — Academic profile. OPTIONAL.
// Per BUILD_PLAN step 16.1 — Exam schedule, study targets.

struct AcademicSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    private let years = ["1st Year", "2nd Year", "3rd Year", "4th Year", "Postgrad", "Not in school"]

    @FocusState
    private var isSchoolFieldFocused: Bool
    /// Name of the directory entry the user tapped; cleared as soon as the
    /// text diverges from it.
    @State
    private var pickedSchool: String?

    private var isSchoolPicked: Bool {
        pickedSchool != nil && pickedSchool == viewModel.university
    }

    private var schoolMatches: [University] {
        UniversityDirectory.shared.search(
            viewModel.university,
            preferredCountryCode: Locale.current.region?.identifier
        )
    }

    private var showSchoolSuggestions: Bool {
        isSchoolFieldFocused && !isSchoolPicked
            && viewModel.university.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                Spacer().frame(height: TempoSpacing.md)

                Text("YOUR ACADEMICS.")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TempoSpacing.screenEdge)

                // University — searchable picker over the bundled
                // UniversityDirectory; free text still accepted for schools
                // that aren't listed.
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text("University / School")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: isSchoolPicked ? "checkmark.circle.fill" : "magnifyingglass")
                            .foregroundStyle(isSchoolPicked ? Color.tempoAmber : .white.opacity(0.5))
                        TextField("Search your school", text: $viewModel.university)
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($isSchoolFieldFocused)
                            .onChange(of: viewModel.university) { _, newValue in
                                pickedSchool = pickedSchool == newValue ? pickedSchool : nil
                            }
                        if !viewModel.university.isEmpty {
                            Button {
                                viewModel.university = ""
                                isSchoolFieldFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .accessibilityLabel("Clear school")
                        }
                    }
                    .padding(TempoSpacing.sm)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSchoolFieldFocused ? Color.tempoAmber : Color.white.opacity(0.15),
                                lineWidth: 1
                            )
                    )

                    if showSchoolSuggestions {
                        schoolSuggestions
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)

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
                .padding(.horizontal, TempoSpacing.screenEdge)

                Spacer()

                HStack {
                    OnboardingSkipButton { viewModel.skip() }
                    Spacer()
                }
                .padding(.horizontal, TempoSpacing.screenEdge)

                OnboardingPrimaryButton(title: "CONTINUE", enabled: true) {
                    viewModel.advance()
                }

                Spacer().frame(height: TempoSpacing.lg)
            }
        }
        .onAppear {
            // Returning to this step: re-mark a previously picked school.
            let saved = viewModel.university
            if UniversityDirectory.shared.search(saved, limit: 1).first?.name == saved {
                pickedSchool = saved
            }
        }
    }
}

// MARK: - School Suggestions

private extension AcademicSetupView {
    var schoolSuggestions: some View {
        let matches = schoolMatches
        let typed = viewModel.university.trimmingCharacters(in: .whitespaces)
        let typedIsListed = matches.contains { $0.name.caseInsensitiveCompare(typed) == .orderedSame }

        return VStack(spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element) { index, school in
                if index > 0 {
                    Divider().overlay(Color.white.opacity(0.08))
                }
                Button {
                    choose(school.name)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(school.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text(school.countryName)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !typedIsListed {
                if !matches.isEmpty {
                    Divider().overlay(Color.white.opacity(0.08))
                }
                Button {
                    choose(typed)
                } label: {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color.tempoAmber)
                        Text(matches.isEmpty ? "Not listed — use \u{201C}\(typed)\u{201D}" : "Use \u{201C}\(typed)\u{201D}")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    func choose(_ name: String) {
        pickedSchool = name
        viewModel.university = name
        isSchoolFieldFocused = false
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    AcademicSetupView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
