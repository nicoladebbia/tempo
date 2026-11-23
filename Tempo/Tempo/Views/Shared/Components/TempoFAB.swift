//
// TempoFAB.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoFAB

// A round floating action button: the mood accent with an ink symbol.

struct TempoFAB: View {
    let icon: String
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood
    @State
    private var taps = 0

    init(icon: String = "plus", action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: icon)
                .font(Tide.title2)
                .foregroundStyle(Tide.ink)
                .frame(width: Tide.s10 + Tide.s4, height: Tide.s10 + Tide.s4)
                .background(mood.accent, in: .circle)
                .shadow(color: mood.accent.opacity(0.4), radius: Tide.s3, y: Tide.s1)
        }
        .buttonStyle(TideFABStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel("Add")
    }
}

// MARK: - TideFABStyle

private struct TideFABStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}
