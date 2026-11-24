//
// EmptyStateView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Empty State View

// A calm glass card with a breathing symbol, one line of what is missing and,
// when there is a next step, a button (and a quieter second one). The spacers stay outside the card so a screen
// that is only this view centres it.

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Tide.s4) {
                TideStateMark(systemName: icon)

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

                if (actionTitle != nil && action != nil) || (secondaryTitle != nil && secondaryAction != nil) {
                    VStack(spacing: Tide.s2) {
                        if let actionTitle, let action {
                            Button(actionTitle, action: action)
                                .buttonStyle(.tidePrimary)
                        }
                        if let secondaryTitle, let secondaryAction {
                            Button(secondaryTitle, action: secondaryAction)
                                .buttonStyle(.tideGlass)
                        }
                    }
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
