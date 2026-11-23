//
// TempoIconButton.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoIconButton

// A bare symbol with a 44 pt target. Pressing lights it up with a soft fill.

struct TempoIconButton: View {
    let icon: String
    let action: () -> Void

    @Environment(\.isEnabled)
    private var isEnabled
    @State
    private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: icon)
                .font(Tide.headline)
                .foregroundStyle(isEnabled ? Tide.text : Color.tempoTextDisabled)
                .frame(width: Tide.hit, height: Tide.hit)
                .contentShape(.rect(cornerRadius: Tide.controlRadius))
        }
        .buttonStyle(TideIconPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}

// MARK: - TideIconPressStyle

private struct TideIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Tide.fillStrong : Color.clear,
                in: .rect(cornerRadius: Tide.controlRadius, style: .continuous)
            )
            .animation(Tide.snap, value: configuration.isPressed)
    }
}
