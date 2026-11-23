//
// TempoToggleStyle.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoToggleStyle

// Tide: the system switch, lit in the day's mood colour, in a row at least
// 44 pt high, with a selection tick when it flips.

struct TempoToggleStyle: ToggleStyle {
    @Environment(\.tideMood)
    private var mood

    func makeBody(configuration: Configuration) -> some View {
        // The system toggle keeps the label and the switch as one VoiceOver
        // element ("<label>, switch button, on").
        Toggle(isOn: configuration.$isOn) {
            configuration.label
        }
        .toggleStyle(.switch)
        .tint(mood.accent)
        .frame(minHeight: Tide.hit)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
    }
}

extension ToggleStyle where Self == TempoToggleStyle {
    static var tempo: TempoToggleStyle {
        TempoToggleStyle()
    }
}
