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
// is the main action; going back, when offered, is quieter.

struct ErrorStateView: View {
    let title: String
    let message: String
    let retryAction: () -> Void
    let backAction: (() -> Void)?

    init(
        title: String = "Something went wrong.",
        message: String = "Check your connection and try again.",
        retryAction: @escaping () -> Void,
        backAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
        self.backAction = backAction
    }

    @State
    private var retries = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Tide.s4) {
                TideIconTile(systemName: "exclamationmark.triangle.fill", tint: Tide.danger, size: Tide.tileLarge)

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
                    Button("Retry") {
                        retries += 1
                        retryAction()
                    }
                    .buttonStyle(.tidePrimary)

                    if let backAction {
                        Button("Go Back", action: backAction)
                            .buttonStyle(.tempoSecondary)
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
