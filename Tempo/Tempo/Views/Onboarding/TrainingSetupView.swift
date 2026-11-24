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
//
// Each question gets the control that fits it: a big yes/no, symbol chips for
// the kind of training, rising pillars for days a week, cards for the split
// and level bars for experience.

struct TrainingSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private struct TrainingType: Hashable {
        let name: String
        let icon: String
    }

    private struct Level: Hashable {
        let name: String
        let detail: String
        let bars: Int
    }

    private let trainingTypes = [
        TrainingType(name: "Gym", icon: "dumbbell.fill"),
        TrainingType(name: "Running", icon: "figure.run"),
        TrainingType(name: "Team Sport", icon: "sportscourt.fill"),
        TrainingType(name: "Other", icon: "ellipsis"),
    ]
    private let splits = ["PPL", "Upper/Lower", "Full Body", "Bro Split", "I Don't Know"]
    private let levels = [
        Level(name: "Beginner", detail: "Less than 1yr consistent", bars: 1),
        Level(name: "Intermediate", detail: "1-3yr, compound lifts OK", bars: 2),
        Level(name: "Advanced", detail: "3+yr, tracking overload", bars: 3),
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
                // Side by side, one under the other at accessibility text sizes.
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Tide.s3))
                    : AnyLayout(HStackLayout(spacing: Tide.s3))
                layout {
                    OnboardingChoiceCard(
                        title: "YES",
                        systemImage: "figure.strengthtraining.traditional",
                        isSelected: viewModel.doesTrain == true,
                        layout: .inline
                    ) {
                        viewModel.doesTrain = true
                    }
                    OnboardingChoiceCard(
                        title: "NO",
                        systemImage: "figure.cooldown",
                        isSelected: viewModel.doesTrain == false,
                        layout: .inline
                    ) {
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
                            OnboardingChip(
                                title: type.name,
                                systemImage: type.icon,
                                isSelected: viewModel.trainingTypes.contains(type.name)
                            ) {
                                if viewModel.trainingTypes.contains(type.name) {
                                    viewModel.trainingTypes.remove(type.name)
                                } else {
                                    viewModel.trainingTypes.insert(type.name)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)

                // Days per week
                VStack(alignment: .leading, spacing: Tide.s3) {
                    OnboardingSectionLabel(
                        "How many days/week?",
                        trailing: "\(viewModel.daysPerWeek) \(viewModel.daysPerWeek == 1 ? "day" : "days")"
                    )
                    // Seven flexible pillars (not fixed-width circles): fixed
                    // widths have an intrinsic total that cannot compress,
                    // which once forced the whole screen wider than the
                    // device. Flexible cells always fit.
                    OnboardingDayPillars(selection: $viewModel.daysPerWeek)
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
                        ForEach(levels, id: \.self) { level in
                            OnboardingOptionRow(
                                title: level.name,
                                subtitle: level.detail,
                                level: level.bars,
                                isSelected: viewModel.experienceLevel == level.name
                            ) {
                                viewModel.experienceLevel = level.name
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
