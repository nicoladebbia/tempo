//
// TrainingLoadCard.swift
// Tempo
//
// Progress → Overview: acute:chronic workload ratio (ACWR) over the last four
// weeks, from Whoop day strain. Same math the readiness brain and safety floor
// use (ReadinessTrendMath.acuteChronicRatio, 30-day window; floor trips above
// TrainingSafetyFloor.acwrCompositeMax), so the chart and the coach agree.
//

import Charts
import SwiftData
import SwiftUI

struct TrainingLoadCard: View {
    @Query(sort: \DailyRecovery.date)
    private var recoveries: [DailyRecovery]

    private static let chartDays = 28
    private static let minStrainDays = 14
    private static let lowBound = 0.8

    private struct Point: Identifiable {
        let date: Date
        let ratio: Double
        var id: Date {
            date
        }
    }

    /// One entry per calendar day over the window the chart needs, nil when
    /// that day has no strain.
    private var dailyStrain: [(date: Date, strain: Double?)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let span = Self.chartDays + ReadinessAssembler.strainWindow
        var byDay: [Date: Double] = [:]
        for row in recoveries {
            if let strain = row.strain {
                byDay[cal.startOfDay(for: row.date)] = strain
            }
        }
        return (0 ..< span).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { ($0, byDay[$0]) }
        }
    }

    private var points: [Point] {
        let days = dailyStrain
        let ratios = ReadinessTrendMath.acuteChronicSeries(
            strainByDay: days.map(\.strain),
            days: Self.chartDays,
            window: ReadinessAssembler.strainWindow
        )
        let dates = days.suffix(Self.chartDays).map(\.date)
        return zip(dates, ratios).compactMap { date, ratio in
            ratio.map { Point(date: date, ratio: $0) }
        }
    }

    var body: some View {
        let points = points
        let strainDays = dailyStrain.suffix(ReadinessAssembler.strainWindow).filter { $0.strain != nil }.count

        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRAINING LOAD")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if let current = points.last?.ratio {
                    Text(String(format: "%.2f · %@", current, zoneLabel(current)))
                        .font(.tempoCaption1)
                        .foregroundStyle(zoneColor(current))
                }
            }

            if points.isEmpty {
                Text(
                    "Building your baseline — \(min(strainDays, Self.minStrainDays))/\(Self.minStrainDays) days of Whoop strain. Keep the strap on."
                )
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                chart(points)
                Text(
                    "Last 7 days vs last 4 weeks. Under 0.8 you're detraining; over \(String(format: "%.1f", TrainingSafetyFloor.acwrCompositeMax)) injury risk climbs and the coach blocks two-a-days."
                )
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func chart(_ points: [Point]) -> some View {
        let high = TrainingSafetyFloor.acwrCompositeMax
        let top = max(high + 0.3, (points.map(\.ratio).max() ?? 0) + 0.1)
        return Chart {
            RectangleMark(
                yStart: .value("Low", Self.lowBound),
                yEnd: .value("High", high)
            )
            .foregroundStyle(Color.tempoRecoveryGreen.opacity(0.12))

            RuleMark(y: .value("Limit", high))
                .foregroundStyle(Color.tempoRecoveryRed.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            ForEach(points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("ACWR", point.ratio)
                )
                .foregroundStyle(Color.tempoSignal)
                .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(
                    x: .value("Day", last.date),
                    y: .value("ACWR", last.ratio)
                )
                .foregroundStyle(zoneColor(last.ratio))
            }
        }
        .chartYScale(domain: 0 ... top)
        .chartYAxis {
            AxisMarks(values: [0, Self.lowBound, high]) { _ in
                AxisGridLine()
                    .foregroundStyle(Color.tempoTextTertiary.opacity(0.2))
                AxisValueLabel()
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(height: 140)
        .accessibilityLabel("Training load, acute to chronic ratio")
        .accessibilityValue(points.last.map { String(format: "%.2f, %@", $0.ratio, zoneLabel($0.ratio)) } ?? "")
    }

    private func zoneLabel(_ ratio: Double) -> String {
        if ratio > TrainingSafetyFloor.acwrCompositeMax {
            return "High"
        }
        if ratio < Self.lowBound {
            return "Low"
        }
        return "Sweet spot"
    }

    private func zoneColor(_ ratio: Double) -> Color {
        if ratio > TrainingSafetyFloor.acwrCompositeMax {
            return .tempoRecoveryRed
        }
        if ratio < Self.lowBound {
            return .tempoRecoveryYellow
        }
        return .tempoRecoveryGreen
    }
}
