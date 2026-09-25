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
                .padding(.top, TempoSpacing.xxxl)
            } else {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    ForEach(archivedPrograms) { program in
                        historyRow(program)
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.lg)
                .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Program History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyRow(_ program: TrainerProgram) -> some View {
        let stats = TrainerProgramHistoryStats.stats(for: program, modelContext: modelContext)
        return VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(dateRange(for: program))
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                Spacer()
                Text(program.scheduleMode.displayName)
                    .font(.tempoCaption2.weight(.semibold))
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            if stats.scheduled > 0 {
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    HStack {
                        Text("\(stats.done) / \(stats.scheduled) sessions done")
                            .font(.tempoCaption1.weight(.semibold))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        Text("\(Int((stats.fraction * 100).rounded()))%")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.tempoDivider)
                            Capsule()
                                .fill(Color.tempoSignal)
                                .frame(width: geo.size.width * stats.fraction)
                        }
                    }
                    .frame(height: 6)
                }
            } else {
                Text("No sessions were ever generated for this program.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPaddingCompact)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl))
    }

    private func dateRange(for program: TrainerProgram) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let start = formatter.string(from: program.startDate)
        guard !program.repeats else {
            return "Started \(start)"
        }
        let end = Calendar.current.date(byAdding: .day, value: program.weeks.count * 7, to: program.startDate) ?? program.startDate
        return "\(start) – \(formatter.string(from: end))"
    }
}
