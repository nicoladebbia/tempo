import SwiftUI

// MARK: - Goal Setup View
// Per WIREFRAMES.md Screen 46 — Goals + Non-negotiables + time-waster + evening time.
// Per STATE_MACHINES.md Section 10 — REQUIRED (primaryGoal must be set).

struct GoalSetupView: View {
    @Bindable var viewModel: OnboardingViewModel

    private let goals = [
        ("Build Muscle", "Gain size and strength"),
        ("Lose Fat", "Cut while keeping muscle"),
        ("Improve Performance", "Sport-specific gains"),
        ("Stay Healthy", "Maintain and prevent"),
        ("All-Around", "Balance everything"),
    ]

    private let timeWasterOptions = ["PS5/Gaming", "Social Media", "Netflix/Streaming", "YouTube", "Other"]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.xxl) {
                Spacer().frame(height: TempoSpacing.lg)

                // Per WIREFRAMES.md Screen 46 — "WHAT ARE YOU FIGHTING FOR?"
                Text("WHAT ARE YOU\nFIGHTING FOR?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TempoSpacing.lg)

                // Primary goal
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text("Primary goal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)

                    ForEach(goals, id: \.0) { name, desc in
                        Button {
                            viewModel.primaryGoal = name
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(desc)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                            }
                            .frame(height: 52)
                            .padding(.horizontal, TempoSpacing.md)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        viewModel.primaryGoal == name ? Color.tempoAmber : Color.white.opacity(0.15),
                                        lineWidth: viewModel.primaryGoal == name ? 2 : 1
                                    )
                            )
                        }
                    }
                }
                .onboardingCard()
                .padding(.horizontal, TempoSpacing.lg)

                // Time-waster
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text("What's your biggest time-waster?")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)

                    FlowLayout(spacing: TempoSpacing.sm, lineSpacing: TempoSpacing.sm) {
                        ForEach(timeWasterOptions, id: \.self) { option in
                            Button {
                                if viewModel.timeWasters.contains(option) {
                                    viewModel.timeWasters.remove(option)
                                } else {
                                    viewModel.timeWasters.insert(option)
                                }
                            } label: {
                                Text(option)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(viewModel.timeWasters.contains(option) ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(viewModel.timeWasters.contains(option) ? Color.tempoAmber : Color.white.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .onboardingCard()
                .padding(.horizontal, TempoSpacing.lg)

                // Evening start time
                // Per WIREFRAMES.md Screen 46 — Time picker, 15min increments
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text("When does your evening start?")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)

                    DatePicker("", selection: $viewModel.eveningStartTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(height: 120)

                    Text("This is when the drill sergeant gets serious.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .onboardingCard()
                .padding(.horizontal, TempoSpacing.lg)

                Spacer()

                OnboardingPrimaryButton(title: "CONTINUE", enabled: viewModel.canContinue) {
                    viewModel.advance()
                }

                Spacer().frame(height: TempoSpacing.lg)
            }
        }
    }
}
