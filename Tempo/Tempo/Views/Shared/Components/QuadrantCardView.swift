import SwiftUI

// MARK: - Dashboard Quadrant Card
// Per DESIGN_SYSTEM.md Section 8.2 — Dashboard Quadrant Card:
// Square 1:1, 12pt padding, module tint bar 3pt top, compact layout.

struct QuadrantCardView: View {

    let moduleIcon: String
    let moduleLabel: String
    let moduleColor: Color
    let metricValue: String
    let secondaryMetric: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: moduleIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(moduleColor)
                    Text(moduleLabel)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                Spacer()

                Text(metricValue)
                    .font(.tempoDataLarge)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text(secondaryMetric)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(TempoSpacing.cardPaddingCompact)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                ZStack(alignment: .top) {
                    Color.tempoSurfaceCard
                    VStack(spacing: 0) {
                        moduleColor.frame(height: 3)
                        Spacer()
                    }
                }
            )
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
        .scaleEffect(isPressed ? 0.96 : 1.0)
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
        .aspectRatio(1, contentMode: .fit)
    }
}
