import SwiftUI

// MARK: - Tempo Toggle Style
// Per DESIGN_SYSTEM.md Section 8.5 — Toggle:
// Signal Red on-color, system standard size 51x31pt, light haptic on toggle.

struct TempoToggleStyle: ToggleStyle {

    @Environment(\.colorScheme) private var colorScheme

    private var onColor: Color {
        colorScheme == .dark
            ? Color(red: 255 / 255, green: 77 / 255, blue: 90 / 255)  // #FF4D5A
            : Color.tempoSignal  // #E63946
    }

    private var offColor: Color {
        colorScheme == .dark
            ? Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)  // #38383A
            : Color.tempoBorder  // #E5E7EB
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Toggle("", isOn: configuration.$isOn)
                .tint(onColor)
                .labelsHidden()
                .onChange(of: configuration.isOn) { _, _ in
                    HapticManager.lightImpact()
                }
        }
    }
}

extension ToggleStyle where Self == TempoToggleStyle {
    static var tempo: TempoToggleStyle { TempoToggleStyle() }
}
