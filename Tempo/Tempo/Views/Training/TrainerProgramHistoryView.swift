//
// TrainerProgramHistoryView.swift
// Tempo
//
// Fix #11(c) — read-only list of finished/archived trainer programs (every
// program that isn't the active one and isn't queued to start later) with
// basic completion stats (`TrainerProgramHistoryStats`). Reached from
// TrainerProgramView's "History" toolbar/list entry.
//

import SwiftData
import SwiftUI

// MARK: - TrainerProgramHistoryView

struct TrainerProgramHistoryView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \TrainerProgram.createdAt, order: .reverse)
    private var allPrograms: [TrainerProgram]

    /// Archived — not active, and not queued to start later (those show as
    /// "Up Next" on `TrainerProgramView`, not history).
    private var archivedPrograms: [TrainerProgram] {
        allPrograms.filter { !$0.isActive && $0.queuedActivationDate == nil }
    }

    var body: some View {
        TrainPlanPage {
            if archivedPrograms.isEmpty {
                TrainEmptyCard(
                    systemImage: "clock.arrow.circlepath",
                    title: "No Program History Yet",
                    message: "Programs you've replaced or finished show up here with how much of them you actually completed."
                )
                .padding(.top, Tide.s4)
            } else {
                ForEach(archivedPrograms) { program in
                    historyRow(program)
                }
            }
        }
        .tidePage()
        .navigationTitle("Program History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyRow(_ program: TrainerProgram) -> some View {
        let stats = TrainerProgramHistoryStats.stats(for: program, modelContext: modelContext)
        return TrainPlanCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Tide.s2) {
                    historyInfo(program)
                    Spacer(minLength: Tide.s2)
                    scheduleLabel(program)
                }
                VStack(alignment: .leading, spacing: Tide.s1) {
                    historyInfo(program)
                    scheduleLabel(program)
                }
            }

            TrainerComplianceBar(stats: stats, emptyText: "No sessions were ever generated for this program.")
        }
    }

    private func historyInfo(_ program: TrainerProgram) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text(program.name)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(dateRange(for: program))
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scheduleLabel(_ program: TrainerProgram) -> some View {
        Text(program.scheduleMode.displayName)
            .font(Tide.caption.weight(.semibold))
            .foregroundStyle(Tide.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Cadence-aware dates — see `TrainerProgramDurationText`.
    private func dateRange(for program: TrainerProgram) -> String {
        TrainerProgramDurationText.historyText(for: program)
    }
}

// MARK: - TrainerComplianceBar

/// "X / Y sessions done  Z%" with a progress capsule — shared by the history
/// rows and the active program card so both read the same.
struct TrainerComplianceBar: View {
    let stats: TrainerProgramHistoryStats.Stats
    var emptyText = "No sessions scheduled yet."

    var body: some View {
        if stats.scheduled > 0 {
            let percent = Int((stats.fraction * 100).rounded())
            VStack(alignment: .leading, spacing: Tide.s2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                        doneLabel
                        Spacer(minLength: Tide.s2)
                        percentLabel(percent)
                    }
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        doneLabel
                        percentLabel(percent)
                    }
                }
                TideLevelBar(progress: stats.fraction, color: Color.accentColor, height: Tide.bar)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(emptyText)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var doneLabel: some View {
        Text("\(stats.done) / \(stats.scheduled) sessions done")
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func percentLabel(_ percent: Int) -> some View {
        TideNumber("\(percent)", unit: "%", size: Tide.numeralS, relativeTo: .title3, color: Color.accentColor)
    }
}
