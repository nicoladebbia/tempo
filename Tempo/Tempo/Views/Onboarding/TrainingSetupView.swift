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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                Spacer().frame(height: TempoSpacing.md)

                // Per WIREFRAMES.md Screen 45 — "LET'S BUILD YOUR TRAINING PROFILE."
                Text("LET'S BUILD YOUR\nTRAINING PROFILE.")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TempoSpacing.screenEdge)

                // Do you train?
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text("Do you train?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)

                    HStack(spacing: TempoSpacing.sm) {
                        togglePill("YES", selected: viewModel.doesTrain == true) {
                            viewModel.doesTrain = true
                        }
                        togglePill("NO", selected: viewModel.doesTrain == false) {
                            viewModel.doesTrain = false
                        }
                    }
                }
                .onboardingCard()
                .padding(.horizontal, TempoSpacing.screenEdge)

                if viewModel.doesTrain == true {
                    // What do you do?
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("What do you do?")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)

                        FlowLayout(spacing: TempoSpacing.sm, lineSpacing: TempoSpacing.sm) {
                            ForEach(trainingTypes, id: \.self) { type in
                                chipButton(type, selected: viewModel.trainingTypes.contains(type)) {
                                    if viewModel.trainingTypes.contains(type) {
                                        viewModel.trainingTypes.remove(type)
                                    } else {
                                        viewModel.trainingTypes.insert(type)
                                    }
                                }
                            }
                        }
                    }
                    .onboardingCard()
                    .padding(.horizontal, TempoSpacing.screenEdge)

                    // Days per week
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("How many days/week?")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)

                        // FlowLayout (not HStack): 7 fixed-36pt circles in an
                        // HStack have a combined intrinsic width that cannot
                        // compress, forcing this card's VStack — and via the
                        // ScrollView, the whole screen — wider than the device
                        // (content rendered 516pt on a 402pt screen, shifted
                        // off the left edge). FlowLayout lets the circles wrap.
                        // Same bug class as GoalSetupView's wheel→compact fix.
                        FlowLayout(spacing: TempoSpacing.xs, lineSpacing: TempoSpacing.xs) {
                            ForEach(1 ... 7, id: \.self) { day in
                                Button {
                                    viewModel.daysPerWeek = day
                                } label: {
                                    Text("\(day)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(viewModel.daysPerWeek == day ? .black : .white)
                                        .frame(width: 36, height: 36)
                                        .background(viewModel.daysPerWeek == day ? Color.tempoAmber : Color.white.opacity(0.1))
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }
                    .onboardingCard()
                    .padding(.horizontal, TempoSpacing.screenEdge)

                    // Preferred split
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("Preferred split?")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)

                        FlowLayout(spacing: TempoSpacing.sm, lineSpacing: TempoSpacing.sm) {
                            ForEach(splits, id: \.self) { split in
                                chipButton(split, selected: viewModel.preferredSplit == split) {
                                    viewModel.preferredSplit = split
                                }
                            }
                        }
                    }
                    .onboardingCard()
                    .padding(.horizontal, TempoSpacing.screenEdge)

                    // Experience level
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("Experience level")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)

                        ForEach(levels, id: \.0) { name, desc in
                            Button {
                                viewModel.experienceLevel = name
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.white)
                                        Text(desc)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    Spacer()
                                }
                                .padding(TempoSpacing.sm)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            viewModel.experienceLevel == name ? Color.tempoAmber : Color.white.opacity(0.15),
                                            lineWidth: viewModel.experienceLevel == name ? 2 : 1
                                        )
                                )
                            }
                        }
                    }
                    .onboardingCard()
                    .padding(.horizontal, TempoSpacing.screenEdge)
                }

                // A bare Spacer() here is broken: inside a ScrollView the
                // content gets unbounded height, so an unconstrained Spacer
                // mis-sizes the stack and the YES content overflows the
                // screen instead of scrolling. Use a fixed gap so the
                // Continue button sits a consistent distance below content.
                Spacer().frame(height: TempoSpacing.xl)

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
    }

    private func togglePill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(selected ? Color.tempoAmber : Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.tempoAmber : Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    TrainingSetupView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
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
        .background(Color.black)
        .preferredColorScheme(.dark)
}
