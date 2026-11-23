//
// ScoreRingView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Score Ring View

// Per DESIGN_SYSTEM.md Section 8.6 — Circular Progress Ring:
// Angular gradient fill, round end cap, center score display, spring animation.

struct ScoreRingView: View {
    let score: Double
    let maxScore: Double
    let label: String
    let size: CGFloat
    let strokeWidth: CGFloat

    @Environment(\.tideMood)
    private var mood

    init(
        score: Double,
        maxScore: Double = 100,
        label: String = "",
        size: CGFloat = 200,
        strokeWidth: CGFloat = 12
    ) {
        self.score = score
        self.maxScore = maxScore
        self.label = label
        self.size = size
        self.strokeWidth = strokeWidth
    }

    private var progress: Double {
        guard maxScore > 0 else {
            return 0
        }
        return min(score / maxScore, 1.0)
    }

    var body: some View {
        if size >= 100, maxScore == 100 {
            TideDial(score: Int(score), caption: label.isEmpty ? "Score" : label, diameter: size)
        } else {
            ring
        }
    }

    private var ring: some View {
        ZStack {
            TideRing(progress: progress, color: mood.accent, lineWidth: strokeWidth)

            // Centre content: hidden when the ring is too small (e.g. a header pill).
            if size >= 60 {
                VStack(spacing: Tide.hair) {
                    TideNumber("\(Int(score))", size: size * 0.3, relativeTo: .title)
                    if !label.isEmpty {
                        Text(label)
                            .font(Tide.label)
                            .foregroundStyle(Tide.text2)
                            .lineLimit(1)
                    }
                }
                .padding(strokeWidth + Tide.s2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.isEmpty ? "Score" : label): \(Int(score)) out of \(Int(maxScore))")
    }
}
