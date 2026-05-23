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


// MARK: - WeeklyTrainingPlanPickerView

/// 7-day picker where the user tags each weekday with a `DayType`. Bound to a
/// `[Int: DayType]` map keyed by `Calendar.current.weekday`. Used in
/// onboarding and in Settings → Profile.
///
/// Tapping a day cycles the type forward through the list; long-press resets
/// it to rest. The cycling order matches the meal-plan calorie multipliers so
/// users see the activity level escalate naturally.
struct WeeklyTrainingPlanPickerView: View {
    @Binding var plan: [Int: DayType]

    /// Display order Mon → Sun for the grid; the binding still uses
    /// Calendar's 1=Sunday … 7=Saturday convention.
    private let displayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    private let cycleOrder: [DayType] = [.rest, .strength, .cardio, .soccer, .double]

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("WEEKLY SCHEDULE")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
                .tracking(1.5)

            Text("Tap a day to set what you're doing. Tempo uses this for calorie targets and meal timing.")
                .font(.tempoFootnote)
                .foregroundStyle(Color.tempoTextSecondary)

            VStack(spacing: TempoSpacing.xs) {
                ForEach(displayOrder, id: \.self) { weekday in
                    dayRow(weekday: weekday)
                }
            }
        }
    }

    @ViewBuilder
    private func dayRow(weekday: Int) -> some View {
        let current = plan[weekday] ?? WeeklyTrainingPlan.defaultPlan[weekday] ?? .strength
        Button {
            HapticManager.selection()
            plan[weekday] = nextType(after: current)
        } label: {
            HStack {
                Text(weekdayName(weekday))
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .frame(width: 110, alignment: .leading)

                Spacer()

                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: icon(for: current))
                        .font(.tempoCaption1)
                        .foregroundStyle(color(for: current))
                    Text(current.displayName)
                        .font(.tempoCallout)
                        .foregroundStyle(color(for: current))
                }
                .padding(.horizontal, TempoSpacing.md)
                .padding(.vertical, 8)
                .background(color(for: current).opacity(0.15))
                .clipShape(Capsule())
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func nextType(after current: DayType) -> DayType {
        guard let idx = cycleOrder.firstIndex(of: current) else {
            return .strength
        }
        return cycleOrder[(idx + 1) % cycleOrder.count]
    }

    private func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return ""
        }
    }

    private func icon(for type: DayType) -> String {
        switch type {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .soccer: return "soccerball"
        case .double: return "bolt.fill"
        case .rest: return "moon.zzz.fill"
        }
    }

    private func color(for type: DayType) -> Color {
        switch type {
        case .strength: return .tempoSignal
        case .cardio: return .tempoElectric
        case .soccer: return .tempoViolet
        case .double: return .tempoAmber
        case .rest: return .tempoTextSecondary
        }
    }
}


// MARK: - WeeklyScheduleSetupView (onboarding step)

/// Onboarding step that wraps the `WeeklyTrainingPlanPickerView` with the
/// standard onboarding chrome (title, skip, continue).
struct WeeklyScheduleSetupView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                Spacer().frame(height: TempoSpacing.md)

                Text("YOUR WEEKLY\nSCHEDULE.")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TempoSpacing.screenEdge)

                WeeklyTrainingPlanPickerView(plan: $viewModel.weeklyTrainingPlan)
                    .onboardingCard()
                    .padding(.horizontal, TempoSpacing.screenEdge)

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
