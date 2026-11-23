//
// TempoButtonStyle.swift
// Tempo
//
// The older button style names, drawn the Tide way: one filled capsule in the
// mood accent for the main action, glass capsules for the rest.
//

import SwiftUI

// MARK: - Primary

struct TempoPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.headline)
            .foregroundStyle(isEnabled ? Tide.ink : Tide.text3)
            .lineLimit(1)
            .minimumScaleFactor(Tide.labelShrink)
            .padding(.horizontal, Tide.s5)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(Tide.fill), in: .capsule)
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.capsule)
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

// MARK: - Secondary

struct TempoSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.headline)
            .foregroundStyle(isEnabled ? Tide.text : Tide.text3)
            .lineLimit(1)
            .minimumScaleFactor(Tide.labelShrink)
            .padding(.horizontal, Tide.s5)
            .frame(maxWidth: .infinity, minHeight: 52)
            .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.capsule)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

// MARK: - Destructive

struct TempoDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.headline)
            .foregroundStyle(isEnabled ? Tide.danger : Tide.text3)
            .lineLimit(1)
            .minimumScaleFactor(Tide.labelShrink)
            .padding(.horizontal, Tide.s5)
            .frame(maxWidth: .infinity, minHeight: 52)
            .glassEffect(.regular.tint(Tide.danger.opacity(0.14)).interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.capsule)
            .sensoryFeedback(.warning, trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

// MARK: - Ghost

struct TempoGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.bodyStrong)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(Tide.text3))
            .frame(maxWidth: .infinity, minHeight: Tide.hit)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.rect)
    }
}

// MARK: - Convenience Extensions

extension ButtonStyle where Self == TempoPrimaryButtonStyle {
    static var tempoPrimary: TempoPrimaryButtonStyle {
        TempoPrimaryButtonStyle()
    }
}

extension ButtonStyle where Self == TempoSecondaryButtonStyle {
    static var tempoSecondary: TempoSecondaryButtonStyle {
        TempoSecondaryButtonStyle()
    }
}

extension ButtonStyle where Self == TempoDestructiveButtonStyle {
    static var tempoDestructive: TempoDestructiveButtonStyle {
        TempoDestructiveButtonStyle()
    }
}

extension ButtonStyle where Self == TempoGhostButtonStyle {
    static var tempoGhost: TempoGhostButtonStyle {
        TempoGhostButtonStyle()
    }
}
