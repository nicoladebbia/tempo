//
// toolbar_new.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import SwiftUI

// MARK: - TempoSymbols

enum TempoSymbols {
    static let settings = "gearshape"
}

// MARK: - TempoSettingsToolbarModifier

struct TempoSettingsToolbarModifier: ViewModifier {
    @Binding
    var isPresented: Bool

    func body(content: Content) -> some View {
        content
            // The field under the page stops while Settings is over it.
            .tideCovered(isPresented)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = true
                    } label: {
                        Image(systemName: TempoSymbols.settings)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .frame(width: Tide.hit, height: Tide.hit)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isPresented) { _, isShown in isShown }
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    DashboardSettingsView()
                }
                .persistenceAlert()
            }
    }
}

// MARK: - TempoSettingsToolbarStandalone

private struct TempoSettingsToolbarStandalone: ViewModifier {
    @State
    private var isPresented = false

    func body(content: Content) -> some View {
        content.modifier(TempoSettingsToolbarModifier(isPresented: $isPresented))
    }
}

extension View {
    func tempoSettingsToolbar(isPresented: Binding<Bool>) -> some View {
        modifier(TempoSettingsToolbarModifier(isPresented: isPresented))
    }

    func tempoSettingsToolbar() -> some View {
        modifier(TempoSettingsToolbarStandalone())
    }
}
