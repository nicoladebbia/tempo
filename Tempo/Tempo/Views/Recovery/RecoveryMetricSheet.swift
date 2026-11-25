//
// RecoveryMetricSheet.swift
// Tempo
//
// The vitals sheet on the Day view: one vital over the last 7 days.
//

import SwiftUI

// MARK: - MetricType

enum MetricType: String, Identifiable, CaseIterable {
    case hrv = "HRV"
    case rhr = "RHR"
    case spo2 = "SpO2"
    case temp = "Temp"

    var id: String {
        rawValue
    }

    /// The name shown on screen. `rawValue` stays the stable English id.
    var title: String {
        switch self {
        case .hrv: "HRV"
        case .rhr: String(localized: "RHR")
        case .spo2: "SpO2"
        case .temp: String(localized: "Temp")
        }
    }

    var unit: String {
        switch self {
        case .hrv: "ms"
        case .rhr: "bpm"
        case .spo2: "%"
        case .temp: "°C"
        }
    }

    var icon: String {
        switch self {
        case .hrv: "waveform.path.ecg"
        case .rhr: "heart.fill"
        case .spo2: "lungs.fill"
        case .temp: "thermometer.medium"
        }
    }
}

// MARK: - MetricTrendSheet

struct MetricTrendSheet: View {
    let metric: MetricType
    @Bindable
    var viewModel: RecoveryViewModel
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        TideScrollPage(spacing: Tide.s5, spacer: Tide.s6) {
            // Header
            HStack(spacing: Tide.s3) {
                TideAreaIconTile(systemName: metric.icon, tint: sparklineColor)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(metric.title)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                    Text("Last 7 days")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                Spacer(minLength: Tide.s2)
                TideInfoButton(explainer: .vital(metric))
                TideCloseButton { dismiss() }
            }
            .accessibilityElement(children: .contain)

            // Sparkline chart
            Group {
                if trendData.count >= 2 {
                    TideLineChart(
                        data: [
                            TempoLineChartData(
                                id: metric.rawValue,
                                label: metric.title,
                                color: sparklineColor,
                                points: trendData.map {
                                    TempoLineChartData<String>.DataPoint(date: $0.0, value: $0.1)
                                }
                            ),
                        ],
                        height: Tide.chartHeight,
                        yDomain: ChartScale.fitted(trendData.map(\.1))
                    )
                } else {
                    RecoveryChartPlaceholder(
                        message: String(localized: "Need \(3 - trendData.count) more days of data to show trends.")
                    )
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

            // Summary stats
            if !trendData.isEmpty {
                HStack(spacing: Tide.s3) {
                    summaryItem(label: String(localized: "Min"), value: trendData.map(\.1).min())
                    summaryItem(label: String(localized: "Avg"), value: trendData.map(\.1).reduce(0, +) / Double(trendData.count))
                    summaryItem(label: String(localized: "Max"), value: trendData.map(\.1).max())
                }
            }
        }
    }

    private func summaryItem(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(label).tideLabel()
            TideNumber(
                value.map { metric == .temp ? $0.tempoDecimal(1) : "\(Int($0))" } ?? "--",
                unit: metric.unit,
                size: Tide.numeralS + Tide.s1,
                relativeTo: .title3
            )
        }
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }

    private var sparklineColor: Color {
        switch metric {
        case .hrv: TideSleepStage.rem
        case .rhr: Tide.danger
        case .spo2: TideTone.mint
        case .temp: TideTone.amber
        }
    }

    private var trendData: [(Date, Double)] {
        let recent = viewModel.recoveries(lastDays: 7)
        switch metric {
        case .hrv:
            return recent.compactMap { r in
                guard let v = r.hrvRmssd else {
                    return nil
                }
                return (r.date, v)
            }
        case .rhr:
            return recent.compactMap { r in
                guard let v = r.restingHR else {
                    return nil
                }
                return (r.date, v)
            }
        case .spo2:
            return recent.compactMap { r in
                guard let v = r.spo2 else {
                    return nil
                }
                return (r.date, v)
            }
        case .temp:
            return recent.compactMap { r in
                guard let v = r.skinTemp else {
                    return nil
                }
                return (r.date, v)
            }
        }
    }
}
