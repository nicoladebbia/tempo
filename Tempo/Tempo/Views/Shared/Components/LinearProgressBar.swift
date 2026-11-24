//
// LinearProgressBar.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Linear Progress Bar

// Per DESIGN_SYSTEM.md Section 8.6 — Linear Progress Bar:
// 6pt default height, fully rounded, spring fill animation.

struct LinearProgressBar: View {
    let progress: Double
    let label: String
    let color: Color
    let height: CGFloat
    let showPercentage: Bool

    @State
    private var animatedProgress: Double = 0
    @ScaledMetric(relativeTo: .footnote)
    private var percentSize: CGFloat = 13

    init(
        progress: Double,
        label: String = "",
        color: Color = .tempoSignal,
        height: CGFloat = 6,
        showPercentage: Bool = true
    ) {
        self.progress = min(max(progress, 0), 1.5) // Allow up to 150% for overfill
        self.label = label
        self.color = color
        self.height = height
        self.showPercentage = showPercentage
    }

    private var fillColor: Color {
        progress > 1.0 ? Color.tempoSuccess : color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            if !label.isEmpty || showPercentage {
                HStack {
                    if !label.isEmpty {
                        Text(label)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                    Spacer()
                    if showPercentage {
                        Text("\(Int(min(progress, 1.0) * 100))%")
                            .font(Tide.numeral(percentSize, .semibold))
                            .foregroundStyle(Tide.text3)
                    }
                }
            }

            TideLevelBar(progress: min(animatedProgress, 1.0), color: fillColor, height: height)
                .background(Tide.fill, in: .capsule)
                .accessibilityHidden(true)
        }
        .onAppear {
            withAnimation(TempoAnimation.springData.delay(0.1)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) {
            withAnimation(TempoAnimation.springData) {
                animatedProgress = progress
            }
        }
        .accessibilityLabel("\(label.isEmpty ? "Progress" : label): \(Int(min(progress, 1.0) * 100)) percent")
    }
}
