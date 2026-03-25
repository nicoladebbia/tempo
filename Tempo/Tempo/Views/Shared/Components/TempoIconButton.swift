import SwiftUI

// MARK: - Icon-Only Button
// Per DESIGN_SYSTEM.md Section 8.1 — 44x44pt touch target, 22pt icon, 12pt radius.

struct TempoIconButton: View {

    let icon: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .background(isPressed ? pressedBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !isPressed else { return }
                    isPressed = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .onEnded { _ in isPressed = false }
        )
    }

    private var iconColor: Color {
        guard isEnabled else { return Color.tempoTextDisabled }
        return colorScheme == .dark ? Color.tempoBone : Color.tempoInk
    }

    private var pressedBackground: Color {
        colorScheme == .dark
            ? Color.tempoBone.opacity(0.12)
            : Color.tempoInk.opacity(0.08)
    }
}
