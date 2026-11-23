//
// TodaySheets.swift
// Tempo
//
// The two sheets Today opens: what is behind the score, and an insight in full.
//

import SwiftUI

// MARK: - InsightDetailSheet

struct InsightDetailSheet: View {
    let vm: DashboardViewModel
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        let insight = vm.currentInsight
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                    // Insight header
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: insight.icon)
                            .font(.tempoTitle1)
                            .foregroundStyle(Color.tempoWarning)
                        Text(insight.detailTitle)
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .padding(.top, TempoSpacing.md)

                    // Main finding
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("FINDING")
                            .font(.tempoModuleTag)
                            .fontWeight(.bold)
                            .tracking(1.2)
                            .foregroundStyle(Color.tempoTextTertiary)

                        Text(insight.detailFinding)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .padding(TempoSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                    // Recommendation
                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("RECOMMENDATION")
                            .font(.tempoModuleTag)
                            .fontWeight(.bold)
                            .tracking(1.2)
                            .foregroundStyle(Color.tempoTextTertiary)

                        HStack(alignment: .top, spacing: TempoSpacing.sm) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.tempoCallout)
                                .foregroundStyle(Color.tempoSignal)
                                .frame(width: 24)

                            Text(insight.detailRecommendation)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                        }
                    }
                    .padding(TempoSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                    // Current status snapshot
                    VStack(alignment: .leading, spacing: TempoSpacing.md) {
                        Text("CURRENT STATUS")
                            .font(.tempoModuleTag)
                            .fontWeight(.bold)
                            .tracking(1.2)
                            .foregroundStyle(Color.tempoTextTertiary)

                        insightMetricRow(
                            icon: "heart.fill",
                            label: "Recovery",
                            value: vm.body.formattedRecovery,
                            color: vm.body.recoveryZone?.color ?? .tempoTextTertiary
                        )

                        insightMetricRow(
                            icon: "moon.fill",
                            label: "Sleep",
                            value: vm.body.formattedSleep,
                            color: sleepColor(vm.body.sleepHours)
                        )

                        insightMetricRow(
                            icon: "book.fill",
                            label: "Study Streak",
                            value: "\(vm.mind.currentStreakDays) days",
                            color: vm.mind.currentStreakDays >= 7 ? .tempoAmber : .tempoTextPrimary
                        )

                        insightMetricRow(
                            icon: "figure.run",
                            label: "Training",
                            value: trainingStatusText(vm.move),
                            color: trainingStatusColor(vm.move)
                        )
                    }
                    .padding(TempoSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.xxxxl)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
        }
    }

    private func insightMetricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.tempoSubheadline)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Text(value)
                .font(.tempoDataMedium)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    private func sleepColor(_ hours: Double?) -> Color {
        guard let hours else {
            return .tempoTextTertiary
        }
        if hours >= 7 {
            return .tempoSuccess
        }
        if hours >= 6 {
            return .tempoWarning
        }
        return .tempoError
    }

    private func trainingStatusText(_ move: MoveQuadrantData) -> String {
        switch move.workoutStatus {
        case .completed: "Done"
        case .planned: "Planned"
        case .restDay: "Rest Day"
        case .none: "No workout"
        }
    }

    private func trainingStatusColor(_ move: MoveQuadrantData) -> Color {
        switch move.workoutStatus {
        case .completed: .tempoSuccess
        case .planned: .tempoAmber
        case .restDay: .tempoTextSecondary
        case .none: .tempoTextTertiary
        }
    }
}

// MARK: - ScoreBreakdownSheet

struct ScoreBreakdownSheet: View {
    let vm: DashboardViewModel
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        let breakdown = vm.scoreBreakdown
        NavigationStack {
            VStack(spacing: TempoSpacing.xl) {
                // Total score hero
                if let score = vm.dailyScore {
                    VStack(spacing: TempoSpacing.xs) {
                        ScoreRingView(
                            score: Double(score),
                            maxScore: 100,
                            size: 80,
                            strokeWidth: 8
                        )
                        Text("\(score)/100")
                            .font(.tempoDataLarge)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text("Daily Score")
                            .font(.tempoFootnote)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .padding(.top, TempoSpacing.lg)
                }

                // Component breakdown
                VStack(spacing: TempoSpacing.md) {
                    scoreComponentRow(
                        icon: "heart.fill",
                        label: "Recovery",
                        points: breakdown.recoveryPoints,
                        maxPoints: 25,
                        isAvailable: breakdown.recoveryAvailable,
                        color: .tempoRecoveryGreen
                    )
                    scoreComponentRow(
                        icon: "fork.knife",
                        label: "Nutrition",
                        points: breakdown.nutritionPoints,
                        maxPoints: 25,
                        isAvailable: breakdown.nutritionAvailable,
                        color: .tempoViolet
                    )
                    scoreComponentRow(
                        icon: "book.fill",
                        label: "Study",
                        points: breakdown.studyPoints,
                        maxPoints: 25,
                        isAvailable: breakdown.studyAvailable,
                        color: .tempoElectric
                    )
                    scoreComponentRow(
                        icon: "figure.run",
                        label: "Movement",
                        points: breakdown.movementPoints,
                        maxPoints: 25,
                        isAvailable: breakdown.movementAvailable,
                        color: .tempoAmber
                    )
                }
                .padding(TempoSpacing.cardPadding)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                Spacer()
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Score Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func scoreComponentRow(
        icon: String, label: String, points: Double,
        maxPoints: Double, isAvailable: Bool, color: Color
    ) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            HStack {
                Image(systemName: icon)
                    .font(.tempoSubheadline)
                    .foregroundStyle(isAvailable ? color : Color.tempoTextTertiary)
                    .frame(width: 20)

                Text(label)
                    .font(.tempoSubheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isAvailable ? Color.tempoTextPrimary : Color.tempoTextTertiary)

                Spacer()

                if isAvailable {
                    Text("\(String(format: "%.1f", points))/\(Int(maxPoints))")
                        .font(.tempoDataMedium)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.tempoTextPrimary)
                } else {
                    Text("--")
                        .font(.tempoDataMedium)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.tempoBorder.opacity(0.5))
                        .frame(height: 6)
                    if isAvailable {
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * min(points / maxPoints, 1.0), height: 6)
                    }
                }
            }
            .frame(height: 6)
        }
    }
}
