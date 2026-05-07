//
// TempoCardModifier.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - TempoCardModifier

// Per DESIGN_SYSTEM.md Section 8.2 — Standard Card:
// 16pt radius (continuous), 16pt padding, elevation 2 shadow, dark mode 0.5pt border.

struct TempoCardModifier: ViewModifier {
    @Environment(\.colorScheme)
    private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .shadow(
                color: Color.tempoInk.opacity(colorScheme == .dark ? 0 : 0.06),
                radius: 4,
                x: 0,
                y: 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: TempoElevation.cardDarkBorderWidth)
                    .opacity(colorScheme == .dark ? 1 : 0)
            )
    }
}

extension View {
    func tempoCard() -> some View {
        modifier(TempoCardModifier())
    }
}
