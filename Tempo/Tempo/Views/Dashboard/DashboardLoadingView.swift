//
// DashboardLoadingView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Dashboard Loading View

// Per DESIGN_SYSTEM.md §"Primary mark": the wordmark is "TEMPO" in the heavy
// display face, with the "O" replaced by a circular progress ring at 75%
// completion ("a permanent visual reminder that you are never done").
//
// Shown on cold launch while the first data fetch completes. Replaced the
// earlier skeleton screen — the shimmer placeholders read as a half-broken
// dashboard with empty white gaps where values belong, which is not the
// intended first impression. A clean centered brand mark is.

struct DashboardLoadingView: View {
    var body: some View {
        ZStack {
            Color.tempoBgPrimary
                .ignoresSafeArea()

            HStack(spacing: 0) {
                Text("TEMP")
                    .font(.tempoScoreDisplay)
                    .foregroundStyle(Color.tempoTextPrimary)

                // The "O" — a circular progress ring at 75% completion,
                // matching the canonical wordmark treatment. Sized to the
                // cap height of the adjacent glyphs.
                wordmarkRing
                    .padding(.leading, 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tempo")
            .accessibilityAddTraits(.isImage)
        }
    }

    // MARK: - Wordmark Ring ("O")

    private var wordmarkRing: some View {
        ZStack {
            // Faint full track so the gap reads as intentional, not clipped.
            Circle()
                .stroke(
                    Color.tempoBorder.opacity(0.4),
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )

            // 75% complete, gap at top-right — mirrors the app-icon spec.
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.tempoSignal,
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: ringDiameter, height: ringDiameter)
    }

    // Tuned to sit visually as the "O" beside 64pt display glyphs.
    private var ringDiameter: CGFloat { 52 }
    private var ringStroke: CGFloat { 7 }
}

// MARK: - Preview

#Preview {
    DashboardLoadingView()
}
