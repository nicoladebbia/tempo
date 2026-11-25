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
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let insight = vm.currentInsight
        TodaySheetChrome(title: String(localized: "Insight")) {
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

            section(String(localized: "Finding")) {
                Text(insight.detailFinding)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(String(localized: "What to do")) {
                Text(insight.detailRecommendation)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(String(localized: "Right now")) {
                VStack(spacing: Tide.s3) {
                    metricRow(icon: "heart.fill", label: String(localized: "Recovery"), value: vm.body.formattedRecovery)
                    metricRow(icon: "moon.fill", label: String(localized: "Sleep"), value: vm.body.formattedSleep)
                    metricRow(
                        icon: "book.fill", label: String(localized: "Study streak"),
                        value: vm.mind.currentStreakDays == 1 ? String(localized: "1 day") : String(localized: "\(vm.mind.currentStreakDays) days")
                    )
                    metricRow(icon: "figure.run", label: String(localized: "Training"), value: trainingStatusText(vm.move))
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
        let stacks = typeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s3))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                Image(systemName: icon)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.s5)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }
            if !stacks {
                Spacer(minLength: Tide.s2)
            }
            Text(value)
                .font(Tide.numeral(Tide.numeralS))
                .foregroundStyle(Tide.text)
                .padding(.leading, stacks ? Tide.s5 + Tide.s3 : 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func trainingStatusText(_ move: MoveQuadrantData) -> String {
        switch move.workoutStatus {
        case .completed: String(localized: "status.done", defaultValue: "Done", comment: "Status word: a step, task or workout is finished (not the Done button)")
        case .planned: String(localized: "Planned")
        case .restDay: String(localized: "Rest day")
        case .none: String(localized: "No workout")
        }
    }
}

// MARK: - ScoreBreakdownSheet

struct ScoreBreakdownSheet: View {
    let vm: DashboardViewModel

    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// Each of the four parts is worth this much of the 100.
    private static let partMax: Double = 25

    var body: some View {
        let breakdown = vm.scoreBreakdown
        TodaySheetChrome(title: String(localized: "Score breakdown")) {
            if let score = vm.dailyScore {
                RecoveryHero {
                    TideDial(score: score, caption: String(localized: "of 100"), diameter: Tide.dialSheet)
                        .explains(Explainer.dayScore(weakest: Explainer.weakestPart(in: breakdown)).showing(String(localized: "\(score) of 100")))
                } side: {
                    Text("Today's score").tideLabel()
                    Text("Four parts, up to \(Int(Self.partMax)) points each.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No score yet. It builds as recovery, food, study and movement get data.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Tide.s2)
            }

            VStack(spacing: Tide.s4) {
                row(
                    icon: "heart.fill", label: String(localized: "Recovery"), points: breakdown.recoveryPoints,
                    available: breakdown.recoveryAvailable, explainer: Explainer.recoveryPart
                )
                row(
                    icon: "fork.knife", label: String(localized: "Nutrition"), points: breakdown.nutritionPoints,
                    available: breakdown.nutritionAvailable, explainer: Explainer.foodPart(kcalLeft: kcalLeft)
                )
                row(
                    icon: "book.fill", label: String(localized: "Study"), points: breakdown.studyPoints,
                    available: breakdown.studyAvailable, explainer: Explainer.studyPart(minutesLeft: studyMinutesLeft)
                )
                row(
                    icon: "figure.run", label: String(localized: "Movement"), points: breakdown.movementPoints,
                    available: breakdown.movementAvailable,
                    explainer: Explainer.movementPart(
                        stepsTarget: vm.move.stepsTarget, stepsLeft: stepsLeft, sessionDone: vm.move.workoutStatus == .completed
                    )
                )
            }
            .tideCard()
        }
        .presentationDetents([.medium, .large])
    }

    /// Calories still to eat; nil when there is no target.
    private var kcalLeft: Int? {
        vm.fuel.calorieTarget.map { $0 - (vm.fuel.caloriesConsumed ?? 0) }
    }

    /// Study minutes still to do; nil when there is no study target.
    private var studyMinutesLeft: Int? {
        vm.mind.studyTargetMinutes > 0 ? max(0, vm.mind.studyTargetMinutes - vm.mind.studyMinutesToday) : nil
    }

    /// Steps still to walk; nil when there is no step reading or target.
    private var stepsLeft: Int? {
        guard let steps = vm.move.steps, vm.move.stepsTarget > 0 else {
            return nil
        }
        return max(0, vm.move.stepsTarget - steps)
    }

    private func row(icon: String, label: String, points: Double, available: Bool, explainer: Explainer) -> some View {
        // At large text the points drop under the name instead of squeezing it.
        let stacks = typeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s3))
        return VStack(spacing: Tide.s2) {
            layout {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                    Image(systemName: icon)
                        .font(Tide.caption)
                        .foregroundStyle(available ? Tide.text2 : Tide.text3)
                        .frame(width: Tide.s5)
                        .accessibilityHidden(true)
                    Text(label)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(available ? Tide.text : Tide.text3)
                }
                if !stacks {
                    Spacer(minLength: Tide.s2)
                }
                Text(available ? "\(points.formatted(.number.precision(.fractionLength(1)))) / \(Int(Self.partMax))" : String(localized: "No data"))
                    .font(available ? Tide.numeral(Tide.numeralS) : Tide.caption)
                    .foregroundStyle(available ? Tide.text : Tide.text3)
                    .contentTransition(.numericText())
                    .padding(.leading, stacks ? Tide.s5 + Tide.s3 : 0)
            }
            TideLevelBar(progress: available ? min(points / Self.partMax, 1) : 0, height: Tide.bar)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? String(localized: "\(label), \(Int(points.rounded())) of \(Int(Self.partMax)) points") : String(localized: "\(label), no data yet"))
        .explains(explainer)
    }
}
