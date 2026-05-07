//
// TempoButtonStyle.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoPrimaryButtonStyle

// Per DESIGN_SYSTEM.md Section 8.1 — Signal Red bg, Bone White text, 52pt height, 14pt radius.

struct TempoPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.colorScheme)
    private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tempoHeadline)
            .foregroundStyle(isEnabled ? Color.tempoBone : Color.tempoTextDisabled)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
    }

    private func background(isPressed: Bool) -> Color {
        guard isEnabled else {
            return colorScheme == .dark
                ? Color.tempoFillTertiary // #38383A
                : Color.tempoBorder
        }
        if isPressed {
            return colorScheme == .dark
                ? Color.tempoSignal // #E63946
                : Color.tempoSignalPressed // #C1303B
        }
        return colorScheme == .dark
            ? Color.tempoSignalHighlight // #FF4D5A
            : Color.tempoSignal // #E63946
    }
}

// MARK: - TempoSecondaryButtonStyle

// Per DESIGN_SYSTEM.md Section 8.1 — Transparent bg, Ink border 1.5pt, 52pt height.

struct TempoSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.colorScheme)
    private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tempoHeadline)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(configuration.isPressed ? pressedBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }

    private var foregroundColor: Color {
        guard isEnabled else {
            return Color.tempoTextDisabled
        }
        return colorScheme == .dark ? Color.tempoBone : Color.tempoInk
    }

    private var borderColor: Color {
        guard isEnabled else {
            return colorScheme == .dark
                ? Color.tempoFillSecondary // #48484A
                : Color.tempoDividerHeavy
        }
        return colorScheme == .dark ? Color.tempoBone : Color.tempoInk
    }

    private var pressedBackground: Color {
        colorScheme == .dark
            ? Color.tempoBone.opacity(0.10)
            : Color.tempoInk.opacity(0.05)
    }
}

// MARK: - TempoDestructiveButtonStyle

// Per DESIGN_SYSTEM.md Section 8.1 — Transparent bg, Fail Red border 1.5pt.

struct TempoDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.colorScheme)
    private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tempoHeadline)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(configuration.isPressed ? pressedBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
    }

    private var foregroundColor: Color {
        guard isEnabled else {
            return Color.tempoTextDisabled
        }
        return colorScheme == .dark
            ? Color.tempoErrorLight // #F87171
            : Color.tempoError // #DC2626
    }

    private var borderColor: Color {
        guard isEnabled else {
            return colorScheme == .dark
                ? Color.tempoFillSecondary
                : Color.tempoDividerHeavy
        }
        return foregroundColor
    }

    private var pressedBackground: Color {
        colorScheme == .dark
            ? Color.tempoErrorLight.opacity(0.15)
            : Color.tempoError.opacity(0.10)
    }
}

// MARK: - TempoGhostButtonStyle

// Per DESIGN_SYSTEM.md Section 8.1 — No bg/border, Signal Red text, 44pt height, 10pt radius.

struct TempoGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.colorScheme)
    private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tempoSubheadline.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(configuration.isPressed ? pressedBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }

    private var foregroundColor: Color {
        guard isEnabled else {
            return Color.tempoTextDisabled
        }
        return colorScheme == .dark
            ? Color.tempoSignalHighlight // #FF4D5A
            : Color.tempoSignal // #E63946
    }

    private var pressedBackground: Color {
        colorScheme == .dark
            ? Color.tempoSignalHighlight.opacity(0.12)
            : Color.tempoSignal.opacity(0.08)
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
