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

    @Environment(\.colorScheme)
    private var colorScheme

    enum DayStatus {
        case completed
        case missed
        case today(completed: Bool)
        case future
    }

    private var emptyDotColor: Color {
        colorScheme == .dark
            ? Color.tempoFillTertiary
            : Color.tempoBorder
    }

    private var missedBorderColor: Color {
        colorScheme == .dark
            ? Color.tempoSurfaceDeep
            : Color.white
    }

    var body: some View {
        HStack(spacing: TempoSpacing.xs) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, status in
                dotView(for: status)
                    .animation(
                        TempoAnimation.micro.delay(Double(index) * TempoAnimation.staggerDot),
                        value: status.isCompleted
                    )
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func dotView(for status: DayStatus) -> some View {
        switch status {
        case .completed:
            Circle()
                .fill(Color.tempoSignal)
                .frame(width: 8, height: 8)

        case .missed:
            Circle()
                .fill(Color.tempoError)
                .overlay(
                    Circle()
                        .stroke(missedBorderColor, lineWidth: 1)
                )
                .frame(width: 8, height: 8)

        case let .today(completed):
            ZStack {
                if completed {
                    Circle()
                        .fill(Color.tempoSignal)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Color.tempoSignal)
                        .frame(width: 8, height: 8)
                }
                // Pulsing ring for today
                PulsingRing()
            }
            .frame(width: 14, height: 14)

        case .future:
            Circle()
                .fill(emptyDotColor)
                .frame(width: 8, height: 8)
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
    @State
    private var isPulsing = false

    var body: some View {
        Circle()
            .stroke(Color.tempoSignal, lineWidth: 1)
            .scaleEffect(isPulsing ? 1.4 : 1.0)
            .opacity(isPulsing ? 0 : 0.3)
            .frame(width: 8, height: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
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
