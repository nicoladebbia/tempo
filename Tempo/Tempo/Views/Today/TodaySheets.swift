//
// TodaySheets.swift
// Tempo
//
// The two sheets Today opens: what is behind the score, and an insight in full.
// Both are drawn in Tide: the same field, cards and numerals as the page.
//

import SwiftUI

// MARK: - TodaySheetChrome

/// What both sheets share: the Tide field behind, a title, a close button.
private struct TodaySheetChrome<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    content
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s8)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationBackground {
            TideBackground(energy: Tide.sheetEnergy).environment(\.tideMood, mood)
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

// MARK: - InsightDetailSheet

struct InsightDetailSheet: View {
    let vm: DashboardViewModel

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        let insight = vm.currentInsight
        TodaySheetChrome(title: "Insight") {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                Image(systemName: insight.icon)
                    .font(Tide.title2)
                    .foregroundStyle(mood.accent)
                    .accessibilityHidden(true)
                Text(insight.detailTitle)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Tide.s2)

            section("Finding") {
                Text(insight.detailFinding)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("What to do") {
                Text(insight.detailRecommendation)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Right now") {
                VStack(spacing: Tide.s3) {
                    metricRow(icon: "heart.fill", label: "Recovery", value: vm.body.formattedRecovery)
                    metricRow(icon: "moon.fill", label: "Sleep", value: vm.body.formattedSleep)
                    metricRow(
                        icon: "book.fill", label: "Study streak",
                        value: vm.mind.currentStreakDays == 1 ? "1 day" : "\(vm.mind.currentStreakDays) days"
                    )
                    metricRow(icon: "figure.run", label: "Training", value: trainingStatusText(vm.move))
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text(title).tideLabel()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
    }

    private func metricRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
            Image(systemName: icon)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .frame(width: Tide.s5)
                .accessibilityHidden(true)
            Text(label)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
            Spacer(minLength: Tide.s2)
            Text(value)
                .font(Tide.numeral(Tide.numeralS))
                .foregroundStyle(Tide.text)
        }
        .accessibilityElement(children: .combine)
    }

    private func trainingStatusText(_ move: MoveQuadrantData) -> String {
        switch move.workoutStatus {
        case .completed: "Done"
        case .planned: "Planned"
        case .restDay: "Rest day"
        case .none: "No workout"
        }
    }
}

// MARK: - ScoreBreakdownSheet

struct ScoreBreakdownSheet: View {
    let vm: DashboardViewModel

    /// Each of the four parts is worth this much of the 100.
    private static let partMax: Double = 25

    var body: some View {
        let breakdown = vm.scoreBreakdown
        TodaySheetChrome(title: "Score breakdown") {
            if let score = vm.dailyScore {
                TideDial(score: score, caption: "of 100", diameter: Tide.dialSheet)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tide.s2)
            }

            VStack(spacing: Tide.s4) {
                row(icon: "heart.fill", label: "Recovery", points: breakdown.recoveryPoints, available: breakdown.recoveryAvailable)
                row(icon: "fork.knife", label: "Nutrition", points: breakdown.nutritionPoints, available: breakdown.nutritionAvailable)
                row(icon: "book.fill", label: "Study", points: breakdown.studyPoints, available: breakdown.studyAvailable)
                row(icon: "figure.run", label: "Movement", points: breakdown.movementPoints, available: breakdown.movementAvailable)
            }
            .tideCard()
        }
        .presentationDetents([.medium, .large])
    }

    private func row(icon: String, label: String, points: Double, available: Bool) -> some View {
        VStack(spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                Image(systemName: icon)
                    .font(Tide.caption)
                    .foregroundStyle(available ? Tide.text2 : Tide.text3)
                    .frame(width: Tide.s5)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(available ? Tide.text : Tide.text3)
                Spacer(minLength: Tide.s2)
                Text(available ? "\(points.formatted(.number.precision(.fractionLength(1)))) / \(Int(Self.partMax))" : "No data")
                    .font(available ? Tide.numeral(Tide.numeralS) : Tide.caption)
                    .foregroundStyle(available ? Tide.text : Tide.text3)
            }
            TideLevelBar(progress: available ? min(points / Self.partMax, 1) : 0, height: Tide.bar)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? "\(label), \(Int(points.rounded())) of \(Int(Self.partMax)) points" : "\(label), no data yet")
    }
}
