//
// ErrorStateView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Error State View

// Same calm glass card as the empty state, with a danger-tinted symbol. Retry
// is the main action; going back, when offered, is quieter. Both are optional:
// with no retry action there is no Retry button, and the title of the main
// action can be changed ("Try again", "Reconnect").

struct ErrorStateView: View {
    let title: String
    let message: String
    let retryAction: (() -> Void)?
    let backAction: (() -> Void)?
    let retryTitle: String

    init(
        title: String = "Something went wrong.",
        message: String = "Check your connection and try again.",
        retryAction: (() -> Void)? = nil,
        backAction: (() -> Void)? = nil,
        retryTitle: String = "Retry"
    ) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
        self.backAction = backAction
        self.retryTitle = retryTitle
    }

    @State
    private var retries = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Tide.s4) {
                TideStateMark(systemName: "exclamationmark.triangle.fill", tint: Tide.danger)

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

                VStack(spacing: Tide.s2) {
                    if let retryAction {
                        Button(retryTitle) {
                            retries += 1
                            retryAction()
                        }
                        .buttonStyle(.tidePrimary)
                    }

                    if let backAction {
                        Button("Go Back", action: backAction)
                            .buttonStyle(.tideGlass)
                    }
                }
                .padding(.top, Tide.s2)
            }
            .frame(maxWidth: .infinity)
            .tideCard(padding: Tide.s6)
            .frame(maxWidth: Tide.stateWidth)
            .sensoryFeedback(.impact(weight: .light), trigger: retries)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tide.edge)
    }
}

#Preview {
    ErrorStateView(retryAction: {}, backAction: {})
        .tidePage()
}
