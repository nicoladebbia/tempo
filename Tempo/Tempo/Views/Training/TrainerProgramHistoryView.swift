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
        ScrollView(.vertical, showsIndicators: false) {
            if archivedPrograms.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No Program History Yet",
                    message: "Programs you've replaced or finished show up here with how much of them you actually completed."
                )
                .padding(.top, Tide.s8)
            } else {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    ForEach(archivedPrograms) { program in
                        historyRow(program)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s4)
                .padding(.bottom, (Tide.s10 + Tide.s2) + (Tide.s10 + Tide.s2))
            }
        }
        .tidePage()
        .navigationTitle("Program History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyRow(_ program: TrainerProgram) -> some View {
        let stats = TrainerProgramHistoryStats.stats(for: program, modelContext: modelContext)
        return VStack(alignment: .leading, spacing: Tide.s1) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(program.name)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text(dateRange(for: program))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                Spacer()
                Text(program.scheduleMode.displayName)
                    .font(Tide.caption.weight(.semibold))
                    .foregroundStyle(Tide.text2)
            }

            TrainerComplianceBar(stats: stats, emptyText: "No sessions were ever generated for this program.")
        }
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
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
            VStack(alignment: .leading, spacing: Tide.hair) {
                HStack {
                    Text("\(stats.done) / \(stats.scheduled) sessions done")
                        .font(Tide.caption.weight(.semibold))
                        .foregroundStyle(Tide.text)
                    Spacer()
                    Text("\(Int((stats.fraction * 100).rounded()))%")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tide.hairline)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * stats.fraction)
                    }
                }
                .frame(height: 6)
            }
        } else {
            Text(emptyText)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
    }
}
