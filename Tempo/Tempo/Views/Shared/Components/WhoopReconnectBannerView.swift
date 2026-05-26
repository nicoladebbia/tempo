//
// WhoopReconnectBannerView.swift
// Tempo
//
// Created by Tempo on 26/05/2026.
//
//

import SwiftUI

// MARK: - WhoopReconnectBannerView
//
// Reusable banner shown on every Whoop-driven surface (Dashboard Body card,
// Recovery Today/Sleep/Strain/Trends) when the Whoop connection is unhealthy.
//
// Per DESIGN_SYSTEM.md Section 8.8 — Banner pattern (left accent bar, tinted
// background, icon + message). Yellow for soft "disconnected/expired" prompt,
// red accent for terminal errors. Tap target triggers a reconnect closure
// owned by the parent — the banner itself does not present sheets.
//
// Render policy (decided in Phase 0 pin A):
//   render when whoop.connectionState matches any of:
//     - .disconnected (and the parent expected data)
//     - .error(_)     (any terminal/transient Whoop failure)
//   never render for .connected or .connecting.

struct WhoopReconnectBannerView: View {
    let state: WhoopConnectionState
    let onReconnect: () -> Void

    init(state: WhoopConnectionState, onReconnect: @escaping () -> Void) {
        self.state = state
        self.onReconnect = onReconnect
    }

    var body: some View {
        if let copy = bannerCopy {
            HStack(spacing: 0) {
                // Left accent bar (yellow for disconnected, red for error).
                copy.accent
                    .frame(width: 4)

                HStack(spacing: TempoSpacing.md) {
                    Image(systemName: copy.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(copy.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.title)
                            .font(.tempoBody)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text(copy.message)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }

                    Spacer(minLength: TempoSpacing.sm)

                    Button(action: onReconnect) {
                        Text("RECONNECT")
                            .font(.tempoCaption1)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .padding(.horizontal, TempoSpacing.md)
                            .padding(.vertical, TempoSpacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(copy.accent, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reconnect Whoop")
                }
                .padding(.horizontal, TempoSpacing.lg)
                .padding(.vertical, TempoSpacing.md)
            }
            .frame(minHeight: 56)
            .background(copy.background)
        }
    }

    // MARK: - Copy + styling per state

    private struct BannerCopy {
        let icon: String
        let title: String
        let message: String
        let accent: Color
        let background: Color
    }

    private var bannerCopy: BannerCopy? {
        switch state {
        case .connected, .connecting:
            return nil
        case .disconnected:
            return BannerCopy(
                icon: "heart.slash",
                title: "WHOOP NOT CONNECTED",
                message: "Reconnect to see today's recovery, sleep, and strain.",
                accent: Color.tempoWarning,
                background: Color.tempoRecoveryYellowBg
            )
        case .error(let detail):
            return BannerCopy(
                icon: "exclamationmark.triangle.fill",
                title: "WHOOP NEEDS YOU",
                message: detail,
                accent: Color.tempoError,
                background: Color.tempoRecoveryRedBg
            )
        }
    }
}
