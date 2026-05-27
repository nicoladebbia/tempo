//
// WeeklySelfGradeCard.swift
// Tempo
//
// Coach v2.1 Phase 8c — the "Coach grades itself" card. Renders at the
// top of the Coach tab once per ISO week. Counts LearnedOutcome rows
// from the last 7 days, shows the user how Coach is doing, and surfaces
// which preferences had their confidence adjusted.
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §4.
//

import SwiftData
import SwiftUI

// MARK: - WeeklySelfGradeStats

/// Pure summary the view binds to. Computed by `WeeklySelfGradeStats.compute`
/// so the math is unit-testable without a SwiftUI runtime.
struct WeeklySelfGradeStats: Equatable {
    let suggestionsMade: Int
    let takenCount: Int
    let workedWellCount: Int
    let regrettedCount: Int

    var acceptanceRate: Double {
        guard suggestionsMade > 0 else { return 0 }
        return Double(takenCount) / Double(suggestionsMade)
    }

    /// True when there's nothing to report yet (no graded outcomes in
    /// the window). Caller skips rendering rather than showing a
    /// zeroed card.
    var isEmpty: Bool { suggestionsMade == 0 }

    /// Per Phase 8.13: "I made N suggestions, you took M, X went well,
    /// Y you regretted." Single line.
    var summaryLine: String {
        "I made \(suggestionsMade) suggestion\(suggestionsMade == 1 ? "" : "s"), you took \(takenCount), \(workedWellCount) went well, \(regrettedCount) you regretted."
    }

    static func compute(
        outcomes: [LearnedOutcome],
        today: Date = Date(),
        windowDays: Int = 7
    ) -> WeeklySelfGradeStats {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: today) else {
            return .empty
        }
        let recent = outcomes.filter {
            $0.gradedAt != nil && $0.gradedAt! >= cutoff
        }
        // "Suggestions made" = total graded rows. "You took" = outcomes
        // that aren't .abandoned (the user followed through OR the action
        // landed even if the result was unclear / bad). Reflects acceptance,
        // not goodness.
        let suggestions = recent.count
        let taken = recent.filter { row in
            guard let outcome = row.outcome else { return false }
            return outcome != .abandoned
        }.count
        // userOverride is the user explicitly saying "this didn't work
        // for me" even when the data suggested otherwise. It must EXCLUDE
        // the row from the workedWell tally regardless of what the
        // automated outcome said.
        let workedWell = recent.filter { $0.isPositive && !$0.userOverride }.count
        let regretted = recent.filter(\.isNegative).count
        return WeeklySelfGradeStats(
            suggestionsMade: suggestions,
            takenCount: taken,
            workedWellCount: workedWell,
            regrettedCount: regretted
        )
    }

    static let empty = WeeklySelfGradeStats(
        suggestionsMade: 0,
        takenCount: 0,
        workedWellCount: 0,
        regrettedCount: 0
    )
}

// MARK: - WeeklySelfGradeCard

struct WeeklySelfGradeCard: View {
    let stats: WeeklySelfGradeStats
    /// Top-3 preference adjustments rendered as "subject: oldConf → newConf"
    /// lines. Caller computes from LearnedOutcome → LearnedPreference joins.
    let confidenceAdjustments: [WeeklyConfidenceAdjustment]
    /// Fires when the user dismisses for the week. The host stores the
    /// ISO-week marker in UserSettings so the card doesn't re-appear.
    let onDismiss: () -> Void

    @State private var expanded: Bool = false

    var body: some View {
        if stats.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            header
            statsGrid
            if !confidenceAdjustments.isEmpty {
                Divider()
                    .background(Color.tempoSteel.opacity(0.3))
                adjustmentsSection
            }
        }
        .padding(TempoSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .fill(Color.tempoSurfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .strokeBorder(Color.tempoSignal.opacity(0.18), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Label("This Week with Coach", systemImage: "chart.bar.doc.horizontal")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .tracking(TempoTracking.drillLabel)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.tempoTextTertiary)
                    .accessibilityLabel(Text("Dismiss self-grade"))
            }
            .buttonStyle(.plain)
        }
    }

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            row(label: "Suggestions made", value: "\(stats.suggestionsMade)", emphasis: false)
            row(
                label: "You took",
                value: "\(stats.takenCount)  (\(Int((stats.acceptanceRate * 100).rounded()))%)",
                emphasis: false
            )
            row(
                label: "Worked well",
                value: "\(stats.workedWellCount)",
                emphasis: true,
                tint: Color.tempoSuccess
            )
            row(
                label: "You regretted",
                value: "\(stats.regrettedCount)",
                emphasis: true,
                tint: Color.tempoError
            )
        }
    }

    private func row(
        label: String,
        value: String,
        emphasis: Bool,
        tint: Color = .tempoTextPrimary
    ) -> some View {
        HStack {
            Text(label)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Text(value)
                .font(emphasis ? .tempoHeadline : .tempoBody)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var adjustmentsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("I'm adjusting confidence on:")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            ForEach(confidenceAdjustments.prefix(expanded ? confidenceAdjustments.count : 3), id: \.id) { adj in
                adjustmentRow(adj)
            }
            if confidenceAdjustments.count > 3 {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Show all \(confidenceAdjustments.count)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoSignal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func adjustmentRow(_ adj: WeeklyConfidenceAdjustment) -> some View {
        HStack(spacing: TempoSpacing.xs) {
            Image(systemName: adj.delta < 0 ? "arrow.down.right" : "arrow.up.right")
                .foregroundStyle(adj.delta < 0 ? Color.tempoError : Color.tempoSuccess)
                .imageScale(.small)
            Text(adj.subject)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Text(
                String(
                    format: "%.2f → %.2f",
                    adj.oldConfidence,
                    adj.newConfidence
                )
            )
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextTertiary)
            .monospacedDigit()
        }
    }
}

// MARK: - WeeklyConfidenceAdjustment

struct WeeklyConfidenceAdjustment: Equatable, Identifiable {
    let id: UUID
    /// Pref's subject path (e.g. `meal_timing.post_workout`). Caller
    /// passes verbatim; UI doesn't reformat.
    let subject: String
    let oldConfidence: Double
    let newConfidence: Double

    var delta: Double { newConfidence - oldConfidence }
}
