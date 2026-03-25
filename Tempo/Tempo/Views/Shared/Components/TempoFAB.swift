import SwiftUI

// MARK: - Floating Action Button
// Per DESIGN_SYSTEM.md Section 8.1 — 56pt circle, Signal Red, plus icon, elevation 3 shadow.

struct TempoFAB: View {

    let icon: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    init(icon: String = "plus", action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.tempoBone)
                .frame(width: 56, height: 56)
                .background(backgroundColor)
                .clipShape(Circle())
                .shadow(
                    color: shadowColor,
                    radius: 6,
                    x: 0,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Add")
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color.tempoSignalPressed  // #C1303B
        }
        return colorScheme == .dark
            ? Color(red: 255 / 255, green: 77 / 255, blue: 90 / 255)  // #FF4D5A
            : Color.tempoSignal  // #E63946
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.40)
            : Color.tempoInk.opacity(0.20)
    }
}
