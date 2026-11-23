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

        VStack(alignment: .leading, spacing: Tide.s3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Training load")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Spacer(minLength: Tide.s2)
                    currentReading(points.last?.ratio)
                }
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Training load")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    currentReading(points.last?.ratio)
                }
            }

            if points.isEmpty {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text(
                        "Building your baseline — \(min(strainDays, Self.minStrainDays))/\(Self.minStrainDays) days of Whoop strain. Keep the strap on."
                    )
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    TideLevelBar(progress: Double(min(strainDays, Self.minStrainDays)) / Double(Self.minStrainDays))
                }
                .frame(maxWidth: .infinity, minHeight: TideTrainSession.chartEmptyHeight, alignment: .leading)
            } else {
                chart(points)
                Text(
                    "Last 7 days vs last 4 weeks. Under 0.8 you're detraining; over \(String(format: "%.1f", TrainingSafetyFloor.acwrCompositeMax)) injury risk climbs and the coach blocks two-a-days."
                )
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard(padding: Tide.s4)
    }

    @ViewBuilder
    private func currentReading(_ ratio: Double?) -> some View {
        if let current = ratio {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(String(format: "%.2f", current))
                    .font(TideTrain.figure(.title2))
                    .foregroundStyle(zoneColor(current))
                    .contentTransition(.numericText())
                Text(zoneLabel(current))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func chart(_ points: [Point]) -> some View {
        let high = TrainingSafetyFloor.acwrCompositeMax
        let top = max(high + 0.3, (points.map(\.ratio).max() ?? 0) + 0.1)
        return Chart {
            RectangleMark(
                yStart: .value("Low", Self.lowBound),
                yEnd: .value("High", high)
            )
            .foregroundStyle(TideTrain.positive.opacity(TideTrainSession.zoneBandOpacity))

            RuleMark(y: .value("Limit", high))
                .foregroundStyle(Tide.danger.opacity(TideTrainSession.limitLineOpacity))
                .lineStyle(StrokeStyle(lineWidth: TideTrainSession.rule, dash: TideTrainSession.limitDash))

            ForEach(points) { point in
                LineMark(
                    x: .value("Day", point.date),
                    y: .value("ACWR", point.ratio)
                )
                .foregroundStyle(Color.accentColor)
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
                    .foregroundStyle(Tide.text3.opacity(TideTrainSession.gridOpacity))
                AxisValueLabel()
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .frame(height: TideTrainSession.chartHeight)
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
            return Tide.danger
        }
        if ratio < Self.lowBound {
            return TideTrain.caution
        }
        return TideTrain.positive
    }
}
