//
// TempoCardModifier.swift
// Tempo
//
// The standard card of the older screens, now a Tide glass surface.
//

import SwiftUI

struct TempoCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(TempoSpacing.cardPadding)
            .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: TempoRadius.xxxl))
    }
}

extension View {
    func tempoCard() -> some View {
        modifier(TempoCardModifier())
    }
}
