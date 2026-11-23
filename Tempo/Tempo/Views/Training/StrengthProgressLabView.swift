//
// StrengthProgressLabView.swift
// Tempo
//
// §11.2 — the interactive Strength Lab: a scrubbable e1RM curve per lift
// (drag to inspect any session), star markers on PR sessions, a ghost
// compare lift, and a synced session-volume bar chart. Hosted as the "Lab"
// tab of ProgressChartsView; math lives in ProgressLabMath (pure, tested).
//

import Charts
import SwiftData
import SwiftUI

struct StrengthProgressLabView: View {
    @Query(sort: \ExerciseHistory.date, order: .reverse)
    private var allHistory: [ExerciseHistory]
    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]
    @Query
    private var userSettings: [UserSettings]

    @State
    private var primaryID: UUID?
    @State
    private var compareID: UUID?
    @State
    private var span: ProgressLabMath.Span = .quarter
    @State
    private var scrubDate: Date?

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    /// Lifts with history, most-trained first — the chip row's order.
    private var rankedLifts: [Exercise] {
        exercises
            .filter { !($0.history?.isEmpty ?? true) }
            .sorted { ($0.history?.count ?? 0) > ($1.history?.count ?? 0) }
    }

    private var primaryLift: Exercise? {
        rankedLifts.first { $0.id == primaryID } ?? rankedLifts.first
    }

    private var compareLift: Exercise? {
        rankedLifts.first { $0.id == compareID }
    }

    private func points(for exercise: Exercise?) -> [ProgressLabMath.SessionPoint] {
        guard let exercise else {
            return []
        }
        let raw = (exercise.history ?? []).map { row in
            ProgressLabMath.SessionPoint(
                date: row.date,
                e1RM: row.estimated1RM,
                volume: row.totalVolume,
                bestWeight: row.bestSetWeight,
                bestReps: row.bestSetReps
            )
        }
        return ProgressLabMath.filter(ProgressLabMath.series(from: raw), span: span, now: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            if rankedLifts.isEmpty {
                VStack(spacing: Tide.s3) {
                    Spacer().frame(height: 80)
                    Image(systemName: "chart.xyaxis.line")
                        .font(Tide.largeTitle)
                        .foregroundStyle(Tide.text3)
                    Text("Log workouts to unlock the Lab")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                }
                .frame(maxWidth: .infinity)
            } else {
                liftChips
                controls
                e1RMCard
                volumeCard
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.bottom, (Tide.s10 + Tide.s2) + (Tide.s10 + Tide.s2))
    }

    // MARK: Pickers

    private var liftChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tide.s2) {
                ForEach(rankedLifts.prefix(12), id: \.id) { lift in
                    let isPrimary = lift.id == primaryLift?.id
                    TrainFilterChip(label: lift.name, isSelected: isPrimary) {
                        primaryID = lift.id
                        if compareID == lift.id {
                            compareID = nil
                        }
                        scrubDate = nil
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Picker("Span", selection: $span) {
                ForEach(ProgressLabMath.Span.allCases, id: \.self) { span in
                    Text(span.rawValue).tag(span)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Spacer()

            Menu {
                Button("No compare") { compareID = nil }
                ForEach(rankedLifts.prefix(12).filter { $0.id != primaryLift?.id }, id: \.id) { lift in
                    Button(lift.name) { compareID = lift.id }
                }
            } label: {
                Label(
                    compareLift.map { "vs \($0.name)" } ?? "Compare",
                    systemImage: "arrow.left.arrow.right"
                )
                .font(Tide.caption)
                .lineLimit(1)
                .foregroundStyle(Tide.text2)
            }
        }
        .onChange(of: span) {
            scrubDate = nil
        }
    }

    // MARK: e1RM chart

    private var e1RMCard: some View {
        // A bodyweight session's e1RM is 0 — not a point on a strength curve.
        let primary = points(for: primaryLift).filter { ($0.e1RM ?? 0) > 0 }
        let ghost = points(for: compareLift).filter { ($0.e1RM ?? 0) > 0 }
        let scrubbed = scrubDate.flatMap { ProgressLabMath.nearest(to: $0, in: primary) }

        return VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Estimated 1RM").tideLabel()
                Spacer()
                if let scrubbed {
                    scrubCallout(scrubbed)
                } else if let latest = primary.last?.e1RM {
                    Text(weightLabel(latest))
                        .font(Tide.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }

            if primary.isEmpty {
                Text("No e1RM data in this range.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            } else {
                Chart {
                    ForEach(primary) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("e1RM", display(point.e1RM ?? 0))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.35), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("e1RM", display(point.e1RM ?? 0))
                        )
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                    }

                    ForEach(primary.filter(\.isPR)) { pr in
                        PointMark(
                            x: .value("Date", pr.date),
                            y: .value("e1RM", display(pr.e1RM ?? 0))
                        )
                        .symbol {
                            Image(systemName: "star.fill")
                                .font(Tide.label)
                                .foregroundStyle(TideTrain.caution)
                        }
                    }

                    ForEach(ghost) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Ghost", display(point.e1RM ?? 0)),
                            series: .value("Series", "compare")
                        )
                        .foregroundStyle(TideTrain.violet.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                    }

                    if let scrubbed {
                        RuleMark(x: .value("Scrub", scrubbed.date))
                            .foregroundStyle(Tide.text3.opacity(0.6))
                        PointMark(
                            x: .value("Scrub", scrubbed.date),
                            y: .value("e1RM", display(scrubbed.e1RM ?? 0))
                        )
                        .symbolSize(90)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .chartXSelection(value: $scrubDate)
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisGridLine().foregroundStyle(Tide.text3.opacity(0.15))
                        AxisValueLabel().font(Tide.caption).foregroundStyle(Tide.text3)
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel().font(Tide.caption).foregroundStyle(Tide.text3)
                    }
                }
                .frame(height: 200)

                if compareLift != nil {
                    HStack(spacing: Tide.s3) {
                        Label(primaryLift?.name ?? "", systemImage: "circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Label(compareLift?.name ?? "", systemImage: "circle.dashed")
                            .foregroundStyle(TideTrain.violet)
                    }
                    .font(Tide.caption)
                }
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private func scrubCallout(_ point: ProgressLabMath.SessionPoint) -> some View {
        VStack(alignment: .trailing, spacing: Tide.hair) {
            HStack(spacing: Tide.s1) {
                if point.isPR {
                    Image(systemName: "star.fill")
                        .font(Tide.label)
                        .foregroundStyle(TideTrain.caution)
                }
                Text(weightLabel(point.e1RM ?? 0))
                    .font(Tide.headline)
                    .foregroundStyle(Color.accentColor)
            }
            Text(point.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
            if let reps = point.bestReps, reps > 0 {
                Text("best \(WeightFormat.load(kg: point.bestWeight, unit: weightUnit)) × \(reps)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
        }
    }

    // MARK: Volume chart

    private var volumeCard: some View {
        let primary = points(for: primaryLift)

        return VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Session volume").tideLabel()

            if primary.isEmpty {
                Text("Nothing in this range.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
            } else {
                Chart(primary) { point in
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value("Volume", display(point.volume)),
                        width: .fixed(6)
                    )
                    .foregroundStyle(
                        point.date == scrubDate.flatMap { ProgressLabMath.nearest(to: $0, in: primary) }?.date
                            ? Color.accentColor
                            : Color.accentColor.opacity(0.65)
                    )
                    .clipShape(Capsule())
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisValueLabel().font(Tide.caption).foregroundStyle(Tide.text3)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 90)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    // MARK: Helpers

    private func display(_ kg: Double) -> Double {
        WeightUnit.kg.convert(kg, to: weightUnit)
    }

    private func weightLabel(_ kg: Double) -> String {
        WeightFormat.text(kg: kg, unit: weightUnit)
    }
}
