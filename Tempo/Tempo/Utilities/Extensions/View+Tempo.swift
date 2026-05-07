//
// View+Tempo.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

extension View {
    // Applies standard Tempo card styling (already defined in TempoCardModifier, re-exported here).
    // Note: `.tempoCard()` is defined in TempoCardModifier.swift.

    /// Applies elevation shadow appropriate for light/dark mode.
    func tempoShadow(_ elevation: TempoShadowLevel = .card) -> some View {
        modifier(TempoShadowModifier(level: elevation))
    }

    /// Shimmer loading placeholder effect.
    func shimmer(isActive: Bool = true) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }
}

// MARK: - TempoShadowLevel

enum TempoShadowLevel {
    case card
    case sheet
    case fab
    case popover
}

// MARK: - TempoShadowModifier

private struct TempoShadowModifier: ViewModifier {
    let level: TempoShadowLevel
    @Environment(\.colorScheme)
    private var colorScheme

    func body(content: Content) -> some View {
        switch level {
        case .card:
            content.shadow(
                color: Color.tempoInk.opacity(colorScheme == .dark ? 0 : 0.06),
                radius: 4, x: 0, y: 2
            )
        case .sheet:
            let shadow = colorScheme == .dark ? TempoElevation.sheetDark : TempoElevation.sheetLight
            content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        case .fab:
            let shadow = colorScheme == .dark ? TempoElevation.fabDark : TempoElevation.fabLight
            content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        case .popover:
            let shadow = colorScheme == .dark ? TempoElevation.popoverDark : TempoElevation.popoverLight
            content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        }
    }
}

// MARK: - ShimmerModifier

private struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State
    private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if isActive {
            content
                .redacted(reason: .placeholder)
                .overlay(
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.4),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: phase * geometry.size.width * 1.6 - geometry.size.width * 0.3)
                    }
                )
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }
}
