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
        guard suggestionsMade > 0 else {
            return 0
        }
        return Double(takenCount) / Double(suggestionsMade)
    }

    /// True when there's nothing to report yet (no graded outcomes in
    /// the window). Caller skips rendering rather than showing a
    /// zeroed card.
    var isEmpty: Bool {
        suggestionsMade == 0
    }

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
            guard let outcome = row.outcome else {
                return false
            }
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

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .largeTitle)
    private var ringSize: CGFloat = Tide.dialSheet - Tide.s6
    @State
    private var expanded: Bool = false

    var body: some View {
        if stats.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    private var acceptancePercent: Int {
        Int((stats.acceptanceRate * 100).rounded())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            header
            headline
            statsRow
            if !confidenceAdjustments.isEmpty {
                adjustmentsSection
            }
        }
        .tideCard()
    }

    private var header: some View {
        HStack {
            Text("This week with Coach").tideLabel()
            Spacer(minLength: Tide.s2)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
                    .accessibilityLabel(Text("Dismiss self-grade"))
            }
            .buttonStyle(.plain)
            // The close button is taller than the label beside it; pull it back
            // so the header keeps the card's padding.
            .padding(.vertical, -Tide.s3)
            .padding(.trailing, -Tide.s3)
        }
    }

    /// How much of Coach's advice you took: the one number of the card, in a ring.
    private var headline: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s4))
        return layout {
            ZStack {
                TideRing(progress: stats.acceptanceRate, color: mood.accent, lineWidth: Tide.s2)
                TideNumber("\(acceptancePercent)", unit: "%", size: Tide.numeralS, relativeTo: .headline)
                    .minimumScaleFactor(Tide.labelShrink)
                    .lineLimit(1)
                    .padding(Tide.s3)
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text("of suggestions taken")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Text("You took \(stats.takenCount) of \(stats.suggestionsMade)")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(acceptancePercent) percent of suggestions taken. You took \(stats.takenCount) of \(stats.suggestionsMade)")
        )
    }

    @ViewBuilder
    private var statsRow: some View {
        if typeSize.isAccessibilitySize {
            // One per line: no row of tiles fits at these sizes.
            VStack(spacing: Tide.s2) { statTiles }
        } else {
            Grid(horizontalSpacing: Tide.s2, verticalSpacing: Tide.s2) {
                GridRow {
                    statTile(label: "Suggestions", value: stats.suggestionsMade, icon: "text.bubble.fill", tint: Tide.text2)
                    statTile(label: "You took", value: stats.takenCount, icon: "checkmark.circle.fill", tint: Tide.text2)
                }
                GridRow {
                    statTile(label: "Worked well", value: stats.workedWellCount, icon: "hand.thumbsup.fill", tint: Tide.good)
                    statTile(
                        label: "Regretted", value: stats.regrettedCount,
                        icon: "arrow.uturn.backward.circle.fill", tint: Tide.danger
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var statTiles: some View {
        statTile(label: "Suggestions", value: stats.suggestionsMade, icon: "text.bubble.fill", tint: Tide.text2)
        statTile(label: "You took", value: stats.takenCount, icon: "checkmark.circle.fill", tint: Tide.text2)
        statTile(label: "Worked well", value: stats.workedWellCount, icon: "hand.thumbsup.fill", tint: Tide.good)
        statTile(
            label: "Regretted", value: stats.regrettedCount,
            icon: "arrow.uturn.backward.circle.fill", tint: Tide.danger
        )
    }

    private func statTile(label: String, value: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: Tide.s2) {
            TideIconTile(systemName: icon, tint: tint, size: Tide.tile - Tide.s2).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                TideNumber("\(value)", size: Tide.numeralS, relativeTo: .headline, color: Tide.text)
                // One line, shrinking a little, so "Suggestions" is never split
                // mid-word; accessibility sizes get a full-width tile and may wrap.
                Text(label)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(Tide.labelShrink)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
            }
            Spacer(minLength: 0)
        }
        .padding(Tide.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var adjustmentsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Rectangle().fill(Tide.hairline).frame(height: TideCoach.rule)
                .accessibilityHidden(true)
            Text("I'm adjusting confidence on")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .padding(.top, Tide.s1)
            ForEach(confidenceAdjustments.prefix(expanded ? confidenceAdjustments.count : 3), id: \.id) { adj in
                adjustmentRow(adj)
            }
            if confidenceAdjustments.count > 3 {
                Button {
                    withAnimation(Tide.snap) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Show all \(confidenceAdjustments.count)")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(mood.accent)
                        .frame(minHeight: Tide.hit, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func adjustmentRow(_ adj: WeeklyConfidenceAdjustment) -> some View {
        let tint = adj.delta < 0 ? Tide.danger : Tide.good
        return HStack(alignment: .center, spacing: Tide.s3) {
            Image(systemName: adj.delta < 0 ? "arrow.down.right" : "arrow.up.right")
                .font(Tide.caption)
                .foregroundStyle(tint)
                .frame(width: Tide.tile - Tide.s2, height: Tide.tile - Tide.s2)
                .background(tint.opacity(0.16), in: .rect(cornerRadius: Tide.controlRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(adj.subject)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                TideNumber(
                    String(format: "%.2f → %.2f", adj.oldConfidence, adj.newConfidence),
                    size: TideCoach.figureSmall, relativeTo: .footnote, weight: .semibold, color: Tide.text2
                )
            }
            Spacer(minLength: Tide.s2)
            TideCoachPill(title: String(format: "%+.2f", adj.delta), color: tint)
        }
        .accessibilityElement(children: .combine)
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

    var delta: Double {
        newConfidence - oldConfidence
    }
}
