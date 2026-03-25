import Charts
import SwiftUI

// MARK: - Tempo Line Chart
// Per DESIGN_SYSTEM.md Section 8.7 — Line Chart:
// 2pt line, area gradient, 6pt data points, scrub gesture with tooltip.

struct TempoLineChart<ID: Hashable>: View {

    let data: [TempoLineChartData<ID>]
    let height: CGFloat
    let showGrid: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPoint: (series: ID, date: Date, value: Double)?

    init(data: [TempoLineChartData<ID>], height: CGFloat = 200, showGrid: Bool = true) {
        self.data = data
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
            AxisMarks(values: .stride(by: .day, count: axisStride)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(gridColor)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
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
                                guard let firstSeries = data.first else { return }
                                let xPosition = value.location.x - geometry[proxy.plotFrame!].origin.x
                                guard let date: Date = proxy.value(atX: xPosition) else { return }
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
            ? Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)
            : Color.tempoBorder
    }

    private var axisStride: Int {
        let totalPoints = data.first?.points.count ?? 7
        if totalPoints <= 7 { return 1 }
        if totalPoints <= 30 { return 7 }
        return 14
    }

    @ViewBuilder
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

// MARK: - Data Types

struct TempoLineChartData<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    let color: Color
    let points: [DataPoint]

    struct DataPoint: Sendable {
        let date: Date
        let value: Double
    }
}
