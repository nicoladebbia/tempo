//
// EmptyStateView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Empty State View

// Per DESIGN_SYSTEM.md Section 8.11 — Empty States:
// Centered layout, 48pt icon (Ultralight, Ash), Title 3, Body, optional CTA.

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)

            Text(title)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, TempoSpacing.lg)

            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, TempoSpacing.sm)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.tempoPrimary)
                    .padding(.horizontal, TempoSpacing.xxxxl)
                    .padding(.top, TempoSpacing.xxl)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }
}
