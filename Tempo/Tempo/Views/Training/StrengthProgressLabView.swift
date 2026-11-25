//
// StrengthProgressLabView.swift
// Tempo
//
// §11.2 — the interactive Strength Lab: a scrubbable e1RM curve per lift
// (drag to inspect any session), star markers on PR sessions, a ghost
// compare lift, and a synced session-volume bar chart. Hosted at the top of
// the "Lifts" tab of ProgressChartsView; math lives in ProgressLabMath (pure,
// tested).
//

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
                TrainEmptyCard(systemImage: "chart.xyaxis.line", title: String(localized: "Log workouts to see your lifts"))
            } else {
                liftChips
                controls
                e1RMCard
                volumeCard
            }
        }
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
        .scrollClipDisabled()
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                spanTabs
                    .frame(maxWidth: TideTrain.tabsCompact)
                Spacer(minLength: Tide.s2)
                compareMenu
            }
            VStack(alignment: .leading, spacing: Tide.s2) {
                spanTabs
                compareMenu
            }
        }
        .onChange(of: span) {
            scrubDate = nil
        }
    }

    private var spanTabs: some View {
        TrainPlanTabs(
            items: ProgressLabMath.Span.allCases.map { (tag: $0, label: $0.label) },
            selection: $span
        )
    }

    private var compareMenu: some View {
        Menu {
            Button("No compare") { compareID = nil }
            ForEach(rankedLifts.prefix(12).filter { $0.id != primaryLift?.id }, id: \.id) { lift in
                Button(lift.name) { compareID = lift.id }
            }
        } label: {
            Label(
                compareLift.map { String(localized: "vs \($0.name)") } ?? String(localized: "Compare"),
                systemImage: "arrow.left.arrow.right"
            )
            .font(Tide.bodyStrong)
            .lineLimit(1)
            .foregroundStyle(Tide.text)
            .padding(.horizontal, Tide.s4)
            .frame(minHeight: Tide.hit)
            .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
        }
    }

    // MARK: e1RM chart

    private var e1RMCard: some View {
        // A bodyweight session's e1RM is 0 — not a point on a strength curve.
        let primary = points(for: primaryLift).filter { ($0.e1RM ?? 0) > 0 }
        let ghost = points(for: compareLift).filter { ($0.e1RM ?? 0) > 0 }
        let scrubbed = scrubDate.flatMap { ProgressLabMath.nearest(to: $0, in: primary) }

        // The label and the number sit side by side while they fit; at large
        // text the number drops under the label instead of squeezing it into
        // a hyphenated "ESTIMAT-ED".
        let value = Group {
            if let scrubbed {
                scrubCallout(scrubbed)
            } else if let latest = primary.last?.e1RM {
                Text(weightLabel(latest))
                    .font(TideTrain.figure(.title3))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
            }
        }
        return TrainPlanCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Tide.s2) {
                    Text("Estimated 1RM").tideLabel()
                        .lineLimit(1)
                    Spacer(minLength: Tide.s2)
                    value
                }
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Estimated 1RM").tideLabel()
                    value
                }
            }

            if primary.isEmpty {
                Text("No e1RM data in this range.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, minHeight: TideTrain.chartHeight)
            } else {
                TrainPlanTrendChart(
                    points: primary.map {
                        TrainPlanPoint(date: $0.date, value: display($0.e1RM ?? 0), isRecord: $0.isPR)
                    },
                    ghost: ghost.map { TrainPlanPoint(date: $0.date, value: display($0.e1RM ?? 0)) },
                    scrub: $scrubDate
                )

                if compareLift != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Tide.s4) {
                            legendEntries
                            Spacer(minLength: 0)
                        }
                        VStack(alignment: .leading, spacing: Tide.s1) {
                            legendEntries
                        }
                    }
                    .font(Tide.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var legendEntries: some View {
        Label(primaryLift?.name ?? "", systemImage: "circle.fill")
            .foregroundStyle(Color.accentColor)
        Label(compareLift?.name ?? "", systemImage: "circle.dashed")
            .foregroundStyle(TideTrain.violet)
    }

    private func scrubCallout(_ point: ProgressLabMath.SessionPoint) -> some View {
        VStack(alignment: .trailing, spacing: Tide.hair) {
            HStack(spacing: Tide.s1) {
                if point.isPR {
                    Image(systemName: "star.fill")
                        .font(Tide.label)
                        .foregroundStyle(TideTrain.record)
                }
                Text(weightLabel(point.e1RM ?? 0))
                    .font(TideTrain.figure(.title3))
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
        let lit = scrubDate.flatMap { ProgressLabMath.nearest(to: $0, in: primary) }?.date

        return TrainPlanCard(label: String(localized: "Session volume")) {
            if primary.isEmpty {
                Text("Nothing in this range.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .frame(maxWidth: .infinity, minHeight: TideTrain.sparkHeight)
            } else {
                TrainPlanDateBars(
                    points: primary.map { TrainPlanPoint(date: $0.date, value: display($0.volume)) },
                    highlight: lit
                )
            }
        }
    }

    // MARK: Helpers

    private func display(_ kg: Double) -> Double {
        WeightUnit.kg.convert(kg, to: weightUnit)
    }

    private func weightLabel(_ kg: Double) -> String {
        WeightFormat.text(kg: kg, unit: weightUnit)
    }
}
