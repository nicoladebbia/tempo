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
    @Environment(\.tideMood)
    private var mood

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
        OnboardingScaffold(
            title: "YOUR ACADEMICS.",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() },
            skipAction: { viewModel.skip() }
        ) {
            // University — searchable picker over the bundled
            // UniversityDirectory; free text still accepted for schools
            // that aren't listed.
            VStack(alignment: .leading, spacing: Tide.s2) {
                OnboardingSectionLabel("University / School")

                HStack(spacing: Tide.s3) {
                    Image(systemName: isSchoolPicked ? "checkmark.circle.fill" : "magnifyingglass")
                        .font(Tide.headline)
                        .foregroundStyle(isSchoolPicked ? mood.accent : Tide.text3)
                        .accessibilityHidden(true)
                    TextField("", text: $viewModel.university, prompt: Text("Search your school").foregroundStyle(Tide.text3))
                        .font(Tide.headline.weight(.regular))
                        .foregroundStyle(Tide.text)
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
                                .font(Tide.headline)
                                .foregroundStyle(Tide.text3)
                                .frame(width: Tide.hit, height: Tide.hit)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear school")
                        .padding(.trailing, -Tide.s3)
                    }
                }
                .tideFieldSurface(focused: isSchoolFieldFocused)

                if showSchoolSuggestions {
                    schoolSuggestions
                        .transition(.opacity)
                }
            }
            .animation(Tide.snap, value: showSchoolSuggestions)

            // Year of study
            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("Year of Study")
                VStack(spacing: Tide.s2) {
                    ForEach(years, id: \.self) { year in
                        OnboardingOptionRow(title: year, isSelected: viewModel.yearOfStudy == year) {
                            viewModel.yearOfStudy = year
                        }
                    }
                }
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
                    Divider().overlay(Tide.hairline)
                }
                Button {
                    choose(school.name)
                } label: {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(school.name)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .multilineTextAlignment(.leading)
                        Text(school.countryName)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                    .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                    .padding(.horizontal, Tide.s4)
                    .padding(.vertical, Tide.s2)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if !typedIsListed {
                if !matches.isEmpty {
                    Divider().overlay(Tide.hairline)
                }
                Button {
                    choose(typed)
                } label: {
                    HStack(spacing: Tide.s2) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(mood.accent)
                        Text(matches.isEmpty ? "Not listed — use \u{201C}\(typed)\u{201D}" : "Use \u{201C}\(typed)\u{201D}")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                    .padding(.horizontal, Tide.s4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: Tide.tileRadius))
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
        .tidePage(energy: 1)
}
