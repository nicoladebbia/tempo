import SwiftUI

// MARK: - Workout Card
// Per DESIGN_SYSTEM.md Section 8.2 — Workout Card:
// 16pt radius, 16pt padding, Signal Red left accent bar 4pt, auto height (min 120pt).

struct WorkoutCardView: View {

    let name: String
    let exerciseCount: Int
    let estimatedMinutes: Int
    let muscleGroups: [String]
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Left accent bar
                Color.tempoSignal
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    HStack {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.tempoSignal)
                        Text(name)
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        Text("\(estimatedMinutes) min")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    Text("\(exerciseCount) exercises")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)

                    if !muscleGroups.isEmpty {
                        HStack(spacing: TempoSpacing.xs) {
                            ForEach(muscleGroups, id: \.self) { group in
                                Text(group)
                                    .font(.tempoModuleTag)
                                    .tracking(TempoTracking.moduleTag)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Color.tempoTextTertiary)
                                    .padding(.horizontal, TempoSpacing.sm)
                                    .padding(.vertical, TempoSpacing.xxs)
                                    .background(Color.tempoInk.opacity(0.05))
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: TempoRadius.pill, style: .continuous)
                                    )
                            }
                        }
                    }
                }
                .padding(TempoSpacing.cardPadding)
            }
            .frame(minHeight: 120)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .shadow(
                color: Color.tempoInk.opacity(colorScheme == .dark ? 0 : 0.06),
                radius: 4, x: 0, y: 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 0.5)
                    .opacity(colorScheme == .dark ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(TempoAnimation.springMedium, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { _ in isPressed = false }
        )
    }
}
