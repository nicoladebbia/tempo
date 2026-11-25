//
// ProgressRecordsView.swift
// Tempo
//
// The "Records" tab of the Progress page: every personal record in one
// place. A hero with how many records there are and the latest one, the
// latest few in a card, then the best record of every lift (tap one to open
// the lift). The picking and counting lives in `ProgressRecordsMath`, so the
// rules are tested without a view.
//

import SwiftData
import SwiftUI

// MARK: - ProgressRecordsMath

enum ProgressRecordsMath {
    /// One lift's headline record, with how many records the lift has.
    struct Best: Identifiable {
        let id: String
        let name: String
        let exercise: Exercise?
        let record: PersonalRecord
        let recordCount: Int
    }

    /// Which record speaks for a lift: an estimated 1RM first, then the
    /// heaviest weight, then most reps, then volume.
    static func priority(_ type: PRType) -> Int {
        switch type {
        case .oneRepMax: 0
        case .repMax: 1
        case .mostReps: 2
        case .volume: 3
        }
    }

    /// The lift's name even once its exercise has been deleted.
    static func name(of record: PersonalRecord) -> String {
        record.exercise?.name ?? record.exerciseNameSnapshot ?? "Removed exercise"
    }

    private static func key(of record: PersonalRecord) -> String {
        if let exercise = record.exercise {
            return exercise.id.uuidString
        }
        return "name:\(name(of: record).lowercased())"
    }

    /// One row per lift: its highest-priority record type, the biggest value of
    /// that type (the newest on a tie). Lifts are ordered by their most recent
    /// record, newest first.
    static func bestPerExercise(_ records: [PersonalRecord]) -> [Best] {
        let grouped = Dictionary(grouping: records, by: key(of:))
        let rows: [(latest: Date, best: Best)] = grouped.map { key, group in
            let topPriority = group.map { priority($0.type) }.min() ?? 0
            let pool = group.filter { priority($0.type) == topPriority }
            let headline = pool.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.date < rhs.date : lhs.value < rhs.value
            } ?? group[0]
            let best = Best(
                id: key,
                name: name(of: headline),
                exercise: headline.exercise,
                record: headline,
                recordCount: group.count
            )
            return (group.map(\.date).max() ?? headline.date, best)
        }
        return rows.sorted { $0.latest > $1.latest }.map(\.best)
    }

    /// The newest records first, at most `limit`.
    static func recent(_ records: [PersonalRecord], limit: Int) -> [PersonalRecord] {
        Array(records.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// How many records were set in the last `days` days.
    static func count(_ records: [PersonalRecord], lastDays days: Int, now: Date = Date()) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return records.count { $0.date >= cutoff }
    }

    /// What kind of record this is, in words ("Estimated 1RM", "Heaviest weight, 5 reps").
    static func kind(_ record: PersonalRecord) -> String {
        switch record.type {
        case .oneRepMax:
            return "Estimated 1RM"
        case .repMax:
            let reps = record.contextReps.map(String.init) ?? PRDisplay.repsFromContext(record.context)
            if let reps {
                return "Heaviest weight, \(reps) \(reps == "1" ? "rep" : "reps")"
            }
            return "Heaviest weight"
        case .volume:
            return "Best session volume"
        case .mostReps:
            return "Most reps in a set"
        }
    }
}

// MARK: - ProgressRecordsView

struct ProgressRecordsView: View {
    @Query(sort: \PersonalRecord.date, order: .reverse)
    private var records: [PersonalRecord]
    @Query
    private var userSettings: [UserSettings]

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    private static let latestCount = 6

    var body: some View {
        if records.isEmpty {
            TrainEmptyCard(
                systemImage: "star",
                title: "No records yet",
                message: "Every time you lift more than ever before on a lift, it is saved here."
            )
        } else {
            let best = ProgressRecordsMath.bestPerExercise(records)
            VStack(spacing: Tide.s4) {
                hero(best: best)
                latestCard
                bestByLift(best)
            }
        }
    }

    // MARK: Hero

    private func hero(best: [ProgressRecordsMath.Best]) -> some View {
        let lastMonth = ProgressRecordsMath.count(records, lastDays: 30)
        let latest = records.first
        return TrainDayHero(
            label: "Personal records",
            figure: "\(records.count)",
            unit: TrainCount.noun(records.count, "record"),
            caption: latest.map { "Latest: \(ProgressRecordsMath.name(of: $0)), \(PRDisplay.valueLabel($0, unit: weightUnit))" },
            stats: [
                .init(value: "\(lastMonth)", label: "in the last 30 days"),
                .init(value: "\(best.count)", label: TrainCount.noun(best.count, "lift")),
            ],
            figureExplainer: TrainExplainers.personalRecord
        ) {
            Image(systemName: "star.fill")
                .font(Tide.title)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        } footer: {
            Text("Records are saved automatically the moment you beat one.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Latest

    private var latestCard: some View {
        let latest = ProgressRecordsMath.recent(records, limit: Self.latestCount)
        return TrainPlanCard(label: "Latest") {
            ForEach(Array(latest.enumerated()), id: \.element.id) { index, record in
                if index > 0 {
                    TrainPlanDivider()
                }
                latestRow(record)
            }
        }
    }

    private func latestRow(_ record: PersonalRecord) -> some View {
        let info = VStack(alignment: .leading, spacing: Tide.hair) {
            Text(ProgressRecordsMath.name(of: record))
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(ProgressRecordsMath.kind(record)) · \(record.date.formatted(.dateTime.month(.abbreviated).day()))")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        let value = Text(PRDisplay.valueLabel(record, unit: weightUnit))
            .font(Tide.bodyStrong)
            .foregroundStyle(Color.accentColor)
            .fixedSize(horizontal: false, vertical: true)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                info
                Spacer(minLength: Tide.s2)
                value
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                info
                value
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Best by lift

    private func bestByLift(_ best: [ProgressRecordsMath.Best]) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Best by lift", trailing: TrainCount.text(best.count, "lift"))
                .padding(.top, Tide.s2)
            LazyVStack(spacing: Tide.s2) {
                ForEach(best) { row in
                    if let exercise = row.exercise {
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            bestRow(row, opens: true)
                        }
                        .buttonStyle(.trainCard)
                    } else {
                        bestRow(row, opens: false)
                    }
                }
            }
        }
    }

    private func bestRow(_ row: ProgressRecordsMath.Best, opens: Bool) -> some View {
        let info = VStack(alignment: .leading, spacing: Tide.hair) {
            Text(row.name)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Text("\(ProgressRecordsMath.kind(row.record)) · \(row.record.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        let value = Text(PRDisplay.valueLabel(row.record, unit: weightUnit))
            .font(Tide.bodyStrong)
            .foregroundStyle(Color.accentColor)
        let chevron = Image(systemName: "chevron.right")
            .font(Tide.label)
            .foregroundStyle(Tide.text3)
            .opacity(opens ? 1 : 0)
            .accessibilityHidden(true)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                info
                Spacer(minLength: Tide.s2)
                value
                chevron
            }
            HStack(alignment: .top, spacing: Tide.s3) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    info
                    value
                }
                Spacer(minLength: Tide.s2)
                chevron
            }
        }
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}
