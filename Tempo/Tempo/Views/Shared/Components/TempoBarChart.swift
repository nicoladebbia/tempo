import Charts
import SwiftUI

// MARK: - Tempo Bar Chart
// Per DESIGN_SYSTEM.md Section 8.7 — Bar Chart:
// 200pt height, min 16pt bar width, 4-6pt top corner radius, spring draw animation.

struct TempoBarChart<ID: Hashable>: View {

    let series: [TempoBarChartSeries<ID>]
    let height: CGFloat
    let showGrid: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedBar: String?

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
                            topLeadingRadius: 4,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 4
                        )
                    )
                    .opacity(barOpacity(for: bar.label))
                    .position(by: .value("Series", "\(seriesItem.id)"))
                }
            }

            if let selected = selectedBar,
               let bar = firstBar(for: selected) {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top) {
                        Text(String(format: "%.0f", bar.value))
                            .font(.tempoDataSmall)
                            .foregroundStyle(Color.tempoBone)
                            .padding(.horizontal, TempoSpacing.sm)
                            .padding(.vertical, TempoSpacing.xs)
                            .background(Color.tempoInk)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                    }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
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

    private var gridColor: Color {
        colorScheme == .dark
            ? Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)
            : Color.tempoBorder
    }

    private func barOpacity(for label: String) -> Double {
        guard let selected = selectedBar else { return 1.0 }
        return label == selected ? 1.0 : 0.4
    }

    private func firstBar(for label: String) -> TempoBarChartSeries<ID>.Bar? {
        series.first?.bars.first { $0.label == label }
    }
}

// MARK: - Data Types

struct TempoBarChartSeries<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    let color: Color
    let bars: [Bar]

    struct Bar: Sendable {
        let label: String
        let value: Double
    }
}
