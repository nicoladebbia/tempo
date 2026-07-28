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
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            if rankedLifts.isEmpty {
                VStack(spacing: TempoSpacing.md) {
                    Spacer().frame(height: 80)
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("Log workouts to unlock the Lab")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                liftChips
                controls
                e1RMCard
                volumeCard
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
    }

    // MARK: Pickers

    private var liftChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TempoSpacing.sm) {
                ForEach(rankedLifts.prefix(12), id: \.id) { lift in
                    let isPrimary = lift.id == primaryLift?.id
                    Button {
                        primaryID = lift.id
                        if compareID == lift.id {
                            compareID = nil
                        }
                        scrubDate = nil
                        HapticManager.selection()
                    } label: {
                        Text(lift.name)
                            .font(.tempoCaption1)
                            .lineLimit(1)
                            .padding(.horizontal, TempoSpacing.md)
                            .padding(.vertical, TempoSpacing.xs)
                            .background(isPrimary ? Color.tempoAccent : Color.tempoSurfaceCard)
                            .foregroundStyle(isPrimary ? Color.tempoBgPrimary : Color.tempoTextPrimary)
                            .clipShape(Capsule())
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
                .font(.tempoCaption1)
                .lineLimit(1)
                .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .onChange(of: span) {
            scrubDate = nil
        }
    }

    // MARK: e1RM chart

    private var e1RMCard: some View {
        let primary = points(for: primaryLift).filter { $0.e1RM != nil }
        let ghost = points(for: compareLift).filter { $0.e1RM != nil }
        let scrubbed = scrubDate.flatMap { ProgressLabMath.nearest(to: $0, in: primary) }

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("ESTIMATED 1RM")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if let scrubbed {
                    scrubCallout(scrubbed)
                } else if let latest = primary.last?.e1RM {
                    Text(weightLabel(latest))
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoAccent)
                }
            }

            if primary.isEmpty {
                Text("No e1RM data in this range.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
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
                                colors: [Color.tempoAccent.opacity(0.35), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("e1RM", display(point.e1RM ?? 0))
                        )
                        .foregroundStyle(Color.tempoAccent)
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
                                .font(.system(size: 9))
                                .foregroundStyle(Color.tempoAmber)
                        }
                    }

                    ForEach(ghost) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Ghost", display(point.e1RM ?? 0)),
                            series: .value("Series", "compare")
                        )
                        .foregroundStyle(Color.tempoViolet.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                    }

                    if let scrubbed {
                        RuleMark(x: .value("Scrub", scrubbed.date))
                            .foregroundStyle(Color.tempoTextTertiary.opacity(0.6))
                        PointMark(
                            x: .value("Scrub", scrubbed.date),
                            y: .value("e1RM", display(scrubbed.e1RM ?? 0))
                        )
                        .symbolSize(90)
                        .foregroundStyle(Color.tempoAccent)
                    }
                }
                .chartXSelection(value: $scrubDate)
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisGridLine().foregroundStyle(Color.tempoTextTertiary.opacity(0.15))
                        AxisValueLabel().font(.tempoCaption2).foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel().font(.tempoCaption2).foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .frame(height: 200)

                if compareLift != nil {
                    HStack(spacing: TempoSpacing.md) {
                        Label(primaryLift?.name ?? "", systemImage: "circle.fill")
                            .foregroundStyle(Color.tempoAccent)
                        Label(compareLift?.name ?? "", systemImage: "circle.dashed")
                            .foregroundStyle(Color.tempoViolet)
                    }
                    .font(.tempoCaption2)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
    }

    private func scrubCallout(_ point: ProgressLabMath.SessionPoint) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: TempoSpacing.xs) {
                if point.isPR {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.tempoAmber)
                }
                Text(weightLabel(point.e1RM ?? 0))
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoAccent)
            }
            Text(point.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            if let weight = point.bestWeight, let reps = point.bestReps {
                Text("best \(weightLabel(weight)) × \(reps)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
    }

    // MARK: Volume chart

    private var volumeCard: some View {
        let primary = points(for: primaryLift)

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("SESSION VOLUME")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            if primary.isEmpty {
                Text("Nothing in this range.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
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
                            ? Color.tempoAccent
                            : Color.tempoSignal.opacity(0.65)
                    )
                    .clipShape(Capsule())
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisValueLabel().font(.tempoCaption2).foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 90)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
    }

    // MARK: Helpers

    private func display(_ kg: Double) -> Double {
        WeightUnit.kg.convert(kg, to: weightUnit)
    }

    private func weightLabel(_ kg: Double) -> String {
        String(format: "%.0f %@", display(kg), weightUnit.abbreviation)
    }
}
