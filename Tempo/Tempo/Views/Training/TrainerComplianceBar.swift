//
// TrainerComplianceBar.swift
// Tempo
//
// "X / Y sessions done  Z%" with a progress capsule. Used by the Trainer
// page for past programs, so every program reads the same.
//

import SwiftUI

// MARK: - TrainerComplianceBar

struct TrainerComplianceBar: View {
    let stats: TrainerProgramHistoryStats.Stats
    var emptyText = String(localized: "No sessions scheduled yet.")

    var body: some View {
        if stats.scheduled > 0 {
            let percent = Int((stats.fraction * 100).rounded())
            VStack(alignment: .leading, spacing: Tide.s2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                        doneLabel
                        Spacer(minLength: Tide.s2)
                        percentLabel(percent)
                    }
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        doneLabel
                        percentLabel(percent)
                    }
                }
                TideLevelBar(progress: stats.fraction, color: Color.accentColor, height: Tide.bar)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(emptyText)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var doneLabel: some View {
        Text("\(stats.done) / \(stats.scheduled) sessions done")
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func percentLabel(_ percent: Int) -> some View {
        TideNumber("\(percent)", unit: "%", size: Tide.numeralS, relativeTo: .title3, color: Color.accentColor)
    }
}
