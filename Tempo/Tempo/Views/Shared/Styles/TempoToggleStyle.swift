//
// TempoToggleStyle.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoToggleStyle

// Per DESIGN_SYSTEM.md Section 8.5 — Toggle:
// Signal Red on-color, system standard size 51x31pt, light haptic on toggle.

struct TempoToggleStyle: ToggleStyle {
    @Environment(\.colorScheme)
    private var colorScheme

    private var onColor: Color {
        colorScheme == .dark
            ? Color.tempoSignalHighlight
            : Color.tempoSignal
    }

    private var offColor: Color {
        colorScheme == .dark
            ? Color.tempoFillTertiary
            : Color.tempoBorder
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
    static var tempo: TempoToggleStyle {
        TempoToggleStyle()
    }
}
