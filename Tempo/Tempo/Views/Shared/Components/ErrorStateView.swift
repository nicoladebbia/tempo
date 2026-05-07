//
// ErrorStateView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Error State View

// Per DESIGN_SYSTEM.md Section 12.5 — Full-Screen Error:
// Centered layout, exclamationmark icon 48pt Fail Red, retry + go back buttons.

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

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoError)

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

            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button("Retry", action: retryAction)
                    .buttonStyle(.tempoSecondary)

                if let backAction {
                    Button("Go Back", action: backAction)
                        .buttonStyle(.tempoGhost)
                }
            }
            .padding(.horizontal, TempoSpacing.xxxxl)
            .padding(.top, TempoSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }
}
