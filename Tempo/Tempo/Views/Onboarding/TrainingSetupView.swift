//
// TrainingSetupView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Training Setup View

// Per WIREFRAMES.md Screen 45 — Training profile: train?, types, days/week, split, experience.
// Per STATE_MACHINES.md Section 10 — OPTIONAL (can skip).

struct TrainingSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    private let trainingTypes = ["Gym", "Running", "Team Sport", "Other"]
    private let splits = ["PPL", "Upper/Lower", "Full Body", "Bro Split", "I Don't Know"]
    private let levels = [
        ("Beginner", "Less than 1yr consistent"),
        ("Intermediate", "1-3yr, compound lifts OK"),
        ("Advanced", "3+yr, tracking overload"),
    ]

    var body: some View {
        // Per WIREFRAMES.md Screen 45 — "LET'S BUILD YOUR TRAINING PROFILE."
        OnboardingScaffold(
            title: "LET'S BUILD YOUR\nTRAINING PROFILE.",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() },
            skipAction: { viewModel.skip() }
        ) {
            // Do you train?
            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingSectionLabel("Do you train?")
                HStack(spacing: Tide.s2) {
                    OnboardingChip(title: "YES", isSelected: viewModel.doesTrain == true, expands: true) {
                        viewModel.doesTrain = true
                    }
                    OnboardingChip(title: "NO", isSelected: viewModel.doesTrain == false, expands: true) {
                        viewModel.doesTrain = false
                    }
                }
            }

            if viewModel.doesTrain == true {
                // What do you do?
                VStack(alignment: .leading, spacing: Tide.s3) {
                    OnboardingSectionLabel("What do you do?")
                    FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                        ForEach(trainingTypes, id: \.self) { type in
                            OnboardingChip(title: type, isSelected: viewModel.trainingTypes.contains(type)) {
                                if viewModel.trainingTypes.contains(type) {
                                    viewModel.trainingTypes.remove(type)
                                } else {
                                    viewModel.trainingTypes.insert(type)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)

                // Days per week
                VStack(alignment: .leading, spacing: Tide.s3) {
                    OnboardingSectionLabel("How many days/week?")

                    // Seven equal-width cells (not fixed-width circles): fixed
                    // widths have an intrinsic total that cannot compress,
                    // which once forced the whole screen wider than the device
                    // (content rendered 516pt on a 402pt screen, shifted off
                    // the left edge). Flexible cells always fit.
                    HStack(spacing: Tide.s1) {
                        ForEach(1 ... 7, id: \.self) { day in
                            OnboardingChip(title: "\(day)", isSelected: viewModel.daysPerWeek == day, expands: true) {
                                viewModel.daysPerWeek = day
                            }
                        }
                    }
                }
                .transition(.opacity)

                // Preferred split
                VStack(alignment: .leading, spacing: Tide.s3) {
                    OnboardingSectionLabel("Preferred split?")
                    FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                        ForEach(splits, id: \.self) { split in
                            OnboardingChip(title: split, isSelected: viewModel.preferredSplit == split) {
                                viewModel.preferredSplit = split
                            }
                        }
                    }
                }
                .transition(.opacity)

                // Experience level
                VStack(alignment: .leading, spacing: Tide.s3) {
                    OnboardingSectionLabel("Experience level")
                    VStack(spacing: Tide.s2) {
                        ForEach(levels, id: \.0) { name, desc in
                            OnboardingOptionRow(
                                title: name,
                                subtitle: desc,
                                isSelected: viewModel.experienceLevel == name
                            ) {
                                viewModel.experienceLevel = name
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Tide.snap, value: viewModel.doesTrain)
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    TrainingSetupView(viewModel: vm)
        .tidePage(energy: 1)
}

#Preview("Training Active") {
    @Previewable @State
    var vm = {
        let vm = OnboardingViewModel()
        vm.doesTrain = true
        vm.trainingTypes = ["Gym", "Running"]
        vm.daysPerWeek = 5
        vm.preferredSplit = "PPL"
        vm.experienceLevel = "Intermediate"
        return vm
    }()

    TrainingSetupView(viewModel: vm)
        .tidePage(energy: 1)
}
