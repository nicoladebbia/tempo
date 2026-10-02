//
// TempoLineChart.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import SwiftUI

// MARK: - TempoLineChart

// Per DESIGN_SYSTEM.md Section 8.7 — Line Chart:
// 2pt line, area gradient, 6pt data points, scrub gesture with tooltip.

struct TempoLineChart<ID: Hashable>: View {
    let data: [TempoLineChartData<ID>]
    let height: CGFloat
    let showGrid: Bool
    /// When set, x-axis labels follow the date span (about this many) instead
    /// of the per-point stride — for sparse series over a long range.
    let axisDesiredCount: Int?

    @Environment(\.colorScheme)
    private var colorScheme
    @State
    private var selectedPoint: (series: ID, date: Date, value: Double)?

    init(data: [TempoLineChartData<ID>], height: CGFloat = 200, showGrid: Bool = true, axisDesiredCount: Int? = nil) {
        self.data = data
        self.axisDesiredCount = axisDesiredCount
        self.height = height
        self.showGrid = showGrid
    }

    var body: some View {
        Chart {
            ForEach(data) { series in
                ForEach(series.points, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Series", "\(series.id)")
                    )
                    .foregroundStyle(series.color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        series: .value("Series", "\(series.id)")
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [series.color.opacity(0.20), series.color.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(series.color)
                    .symbolSize(36)
                }
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXAxis {
            if let dates = axisDates {
                AxisMarks(values: dates) { _ in xAxisContent }
            } else {
                AxisMarks(values: .stride(by: .day, count: axisStride)) { _ in xAxisContent }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                if showGrid {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(gridColor)
                }
                AxisValueLabel()
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let firstSeries = data.first else {
                                    return
                                }
                                let xPosition = value.location.x - geometry[proxy.plotFrame!].origin.x
                                guard let date: Date = proxy.value(atX: xPosition) else {
                                    return
                                }
                                if let closest = firstSeries.points.min(by: {
                                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                }) {
                                    selectedPoint = (series: firstSeries.id, date: closest.date, value: closest.value)
                                }
                            }
                            .onEnded { _ in selectedPoint = nil }
                    )
            }
        }
        .chartOverlay { _ in
            if let selected = selectedPoint {
                tooltipView(value: selected.value, date: selected.date)
            }
        }
        .frame(height: height)
    }

    private var gridColor: Color {
        colorScheme == .dark
            ? Color.tempoFillTertiary
            : Color.tempoBorder
    }

    @AxisMarkBuilder
    private var xAxisContent: some AxisMark {
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            .foregroundStyle(gridColor)
        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextTertiary)
    }

    /// With `axisDesiredCount`: at most that many tick dates, one per distinct
    /// day among the data, evenly sampled — a short or sparse series never
    /// repeats a label. Nil → the default day stride by point count.
    private var axisDates: [Date]? {
        guard let desired = axisDesiredCount, desired > 0 else {
            return nil
        }
        let calendar = Calendar.current
        // The data's own timestamps (first of each day), so every tick sits
        // inside the plotted domain.
        var seen = Set<Date>()
        let days = (data.first?.points ?? []).map(\.date).sorted().filter {
            seen.insert(calendar.startOfDay(for: $0)).inserted
        }
        guard days.count > desired, desired > 1 else {
            return days
        }
        let step = Double(days.count - 1) / Double(desired - 1)
        return (0 ..< desired).map { days[Int((Double($0) * step).rounded())] }
    }

    private var axisStride: Int {
        let totalPoints = data.first?.points.count ?? 7
        if totalPoints <= 7 {
            return 1
        }
        if totalPoints <= 30 {
            return 7
        }
        return 14
    }

    private func tooltipView(value: Double, date: Date) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text(String(format: "%.1f", value))
                .font(.tempoDataSmall)
                .foregroundStyle(Color.tempoBone)
            Text(date, format: .dateTime.month(.abbreviated).day())
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoAsh)
        }
        .padding(.horizontal, TempoSpacing.cardPaddingCompact)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoInk)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
    }
}

// MARK: - TempoLineChartData

struct TempoLineChartData<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    let color: Color
    let points: [DataPoint]

    struct DataPoint {
        let date: Date
        let value: Double
    }
}
