//
// StreakDotsView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - StreakDotsView

// Per DESIGN_SYSTEM.md Section 8.6 — Streak Dots:
// 8pt dots, 4pt gap. Active = Signal Red, missed = Fail Red + border, future = border only.

struct StreakDotsView: View {
    let days: [DayStatus]

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .caption)
    private var dot: CGFloat = 8

    enum DayStatus {
        case completed
        case missed
        case today(completed: Bool)
        case future
    }

    var body: some View {
        HStack(spacing: Tide.s1 + Tide.hair) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, status in
                dotView(for: status)
                    .animation(
                        Tide.snap.delay(Double(index) * TempoAnimation.staggerDot),
                        value: status.isCompleted
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func dotView(for status: DayStatus) -> some View {
        switch status {
        case .completed:
            Circle()
                .fill(mood.accent)
                .frame(width: dot, height: dot)

        case .missed:
            Circle()
                .fill(Tide.danger.opacity(0.85))
                .frame(width: dot, height: dot)

        case let .today(completed):
            ZStack {
                Circle()
                    .fill(completed ? mood.accent : Tide.track)
                    .frame(width: dot, height: dot)
                // Pulsing ring for today
                PulsingRing(color: mood.accent, size: dot)
            }
            .frame(width: dot * 1.75, height: dot * 1.75)

        case .future:
            Circle()
                .fill(Tide.track)
                .frame(width: dot, height: dot)
        }
    }

    private var activeStreak: Int {
        days.filter(\.isCompleted).count
    }

    private var accessibilityText: String {
        "\(activeStreak) day streak, \(activeStreak > 0 ? "active" : "inactive")"
    }
}

// MARK: - PulsingRing

private struct PulsingRing: View {
    let color: Color
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var isPulsing = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 1)
            .scaleEffect(isPulsing ? 1.7 : 1.0)
            .opacity(isPulsing ? 0 : 0.5)
            .frame(width: size, height: size)
            .onAppear {
                guard !reduceMotion else {
                    return
                }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - DayStatus helpers

extension StreakDotsView.DayStatus {
    var isCompleted: Bool {
        switch self {
        case .completed: true
        case let .today(completed): completed
        case .missed,
             .future: false
        }
    }
}
