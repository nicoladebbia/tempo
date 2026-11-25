//
// TempoBarChart.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import SwiftUI

// MARK: - TempoBarChart

// Per DESIGN_SYSTEM.md Section 8.7 — Bar Chart:
// 200pt height, min 16pt bar width, 4-6pt top corner radius, spring draw animation.

struct TempoBarChart<ID: Hashable>: View {
    let series: [TempoBarChartSeries<ID>]
    let height: CGFloat
    let showGrid: Bool

    @State
    private var selectedBar: String?
    @ScaledMetric(relativeTo: .subheadline)
    private var tipSize: CGFloat = 15

    init(series: [TempoBarChartSeries<ID>], height: CGFloat = 200, showGrid: Bool = true) {
        self.series = series
        self.height = height
        self.showGrid = showGrid
    }

    var body: some View {
        Chart {
            ForEach(series) { seriesItem in
                ForEach(seriesItem.bars, id: \.label) { bar in
                    BarMark(
                        x: .value("Category", bar.label),
                        y: .value("Value", bar.value)
                    )
                    .foregroundStyle(seriesItem.color)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: Tide.s2 - Tide.hair,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: Tide.s2 - Tide.hair
                        )
                    )
                    .opacity(barOpacity(for: bar.label))
                    .position(by: .value("Series", "\(seriesItem.id)"))
                }
            }

            if let selected = selectedBar,
               let bar = firstBar(for: selected)
            {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Tide.text3)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top) {
                        Text(String(format: "%.0f", bar.value))
                            .font(Tide.numeral(tipSize))
                            .foregroundStyle(Tide.text)
                            .padding(.horizontal, Tide.s2)
                            .padding(.vertical, Tide.s1)
                            .glassEffect(.regular.tint(Tide.glassCard), in: .capsule)
                    }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                if showGrid {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Tide.hairline)
                }
                AxisValueLabel()
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
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
                                let xPosition = value.location.x - geometry[proxy.plotFrame!].origin.x
                                if let label: String = proxy.value(atX: xPosition) {
                                    selectedBar = label
                                }
                            }
                            .onEnded { _ in selectedBar = nil }
                    )
            }
        }
        .frame(height: height)
    }

    private func barOpacity(for label: String) -> Double {
        guard let selected = selectedBar else {
            return 1.0
        }
        return label == selected ? 1.0 : 0.4
    }

    private func firstBar(for label: String) -> TempoBarChartSeries<ID>.Bar? {
        series.first?.bars.first { $0.label == label }
    }
}

// MARK: - TempoBarChartSeries

struct TempoBarChartSeries<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    let color: Color
    let bars: [Bar]

    struct Bar {
        let label: String
        let value: Double
    }
}
