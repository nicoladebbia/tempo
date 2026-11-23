//
// EmptyStateView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Empty State View

// A calm glass card with a symbol, one line of what is missing and, when there
// is a next step, one button. The spacers stay outside the card so a screen
// that is only this view centres it.

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

            VStack(spacing: Tide.s4) {
                TideIconTile(systemName: icon, size: Tide.tileLarge)

                VStack(spacing: Tide.s2) {
                    Text(title)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(message)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.tidePrimary)
                        .padding(.top, Tide.s2)
                }
            }
            .frame(maxWidth: .infinity)
            .tideCard(padding: Tide.s6)
            .frame(maxWidth: Tide.stateWidth)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tide.edge)
    }
}

#Preview {
    EmptyStateView(
        icon: "fork.knife",
        title: "No meals yet",
        message: "Log your first meal and today's targets start to fill.",
        actionTitle: "Log a meal",
        action: {}
    )
    .tidePage()
}
