//
// TodaySupplementsCard.swift
// Tempo
//
// Today's supplements, grouped by time of day (Morning / With meals /
// Evening). Each dose is a row: icon, name, dose and time, a big check
// button. Taken rows dim and show when they were taken; shakes show the
// protein / kcal their tick adds; a running-low supplement carries a small
// "3d left" chip that opens the reorder sheet. Tapping a row opens
// that supplement's detail page in Kitchen > Supplements. Ticking goes through the same single path as ever
// (macro "Supplements" entry on tick, removed on untick).
//
// Per DESIGN_SYSTEM.md — tokens only, drill-sergeant voice.
//

import SwiftData
import SwiftUI

struct TodaySupplementsCard: View {
    var viewModel: NutritionTabViewModel
    /// Bumped by the parent when intake logs change elsewhere (notification
    /// action, restock) so the card re-reads.
    var refreshToken = 0

    @Environment(\.modelContext)
    private var modelContext

    @State
    private var reorderTarget: Supplement?
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let board = makeBoard()
        VStack(spacing: 0) {
            if board.total > 0 || !board.skipped.isEmpty {
                card(board)
            }
        }
        .sheet(item: $reorderTarget) { supplement in
            SupplementReorderSheet(supplement: supplement)
        }
    }

    // MARK: - Data

    private func makeBoard() -> SupplementTodayBoard {
        _ = refreshToken
        let doses = viewModel.todaySupplementDoses(modelContext: modelContext)
        guard !doses.isEmpty else {
            return SupplementTodayBoard.build(doses: [], takenAt: [:])
        }
        let shelf = (try? modelContext.fetch(
            FetchDescriptor<Supplement>(predicate: #Predicate<Supplement> { !$0.isArchived })
        )) ?? []
        let byID = Dictionary(shelf.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let windowStart = SupplementReorderService.intakeWindowStart()
        let logs = (try? modelContext.fetch(FetchDescriptor<SupplementIntakeLog>(
            predicate: #Predicate<SupplementIntakeLog> { $0.day >= windowStart }
        ))) ?? []
        var macros: [UUID: MealMacros] = [:]
        var low: [UUID: Int] = [:]
        for (id, supplement) in byID {
            if supplement.hasMacros {
                macros[id] = supplement.macrosPerServing
            }
            if SupplementReorderService.needsReorder(for: supplement, recentLogs: logs),
               let left = SupplementReorderService.daysLeft(for: supplement, recentLogs: logs)
            {
                low[id] = left
            }
        }
        return SupplementTodayBoard.build(
            doses: doses,
            takenAt: SupplementIntakeStore.takenTimes(on: Date(), in: modelContext),
            macros: macros,
            daysLeft: low
        )
    }

    // MARK: - Card

    private func card(_ board: SupplementTodayBoard) -> some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            header(board)
            ForEach(board.sections) { section in
                VStack(alignment: .leading, spacing: 0) {
                    Label(section.period.title, systemImage: section.period.icon)
                        .tideLabel(Tide.text3)
                        .padding(.bottom, Tide.s1)
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle().fill(Tide.hairline).frame(height: 1)
                                .accessibilityHidden(true)
                        }
                        rowView(row)
                    }
                }
            }
            if !board.skipped.isEmpty {
                Text("Skipping today: " + board.skipped.map(\.name).joined(separator: ", "))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
        .accessibilityIdentifier("today.supplements")
    }

    /// Same header as the Water card: icon and label on the left, the count as
    /// a numeral on the right, the bar under both.
    private func header(_ board: SupplementTodayBoard) -> some View {
        let fraction = board.total == 0 ? 0 : Double(board.takenCount) / Double(board.total)
        let title = HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
            Image(systemName: "pills.fill")
                .font(Tide.caption)
                .foregroundStyle(board.allTaken ? Tide.Kitchen.good : mood.accent)
                .accessibilityHidden(true)
            Text("Today's supplements").tideLabel()
        }
        let count = HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
            if board.allTaken {
                Text("All taken")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.Kitchen.good)
            } else {
                TideNumber("\(board.takenCount)", size: Tide.numeralS, relativeTo: .headline)
                    .contentTransition(.numericText())
                Text("/ \(board.total) taken")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(board.allTaken ? "All supplements taken" : "Taken \(board.takenCount) of \(board.total)")
        return VStack(alignment: .leading, spacing: Tide.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    title
                    Spacer(minLength: Tide.s2)
                    count
                }
                VStack(alignment: .leading, spacing: Tide.s2) {
                    title
                    count
                }
            }
            TideLevelBar(progress: fraction, color: board.allTaken ? Tide.Kitchen.good : mood.accent, height: Tide.bar)
                .animation(Tide.lively, value: board.takenCount)
                .accessibilityHidden(true)
        }
    }

    private func rowView(_ row: SupplementBoardRow) -> some View {
        HStack(spacing: Tide.s3) {
            Button {
                viewModel.openSupplement(row.dose.supplementID)
            } label: {
                HStack(spacing: Tide.s3) {
                    // The kind icon gives way to the name at the accessibility sizes.
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: row.dose.kind.icon)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(row.isTaken ? Tide.text3 : mood.accent)
                            .frame(width: Tide.hit, height: Tide.hit)
                            .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(row.dose.name)
                            .font(Tide.headline)
                            .foregroundStyle(row.isTaken ? Tide.text2 : Tide.text)
                            .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                        detailLine(row)
                        if let macros = row.macrosLine {
                            Text(macros)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                                .lineLimit(1)
                        }
                    }
                    .opacity(row.isTaken ? 0.7 : 1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.dose.name), \(row.dose.dosePerServing), \(row.dose.timeLabel). Open details")

            checkButton(row)
        }
        .padding(.vertical, Tide.s2)
    }

    private func detailLine(_ row: SupplementBoardRow) -> some View {
        HStack(spacing: Tide.s1) {
            Text(detailText(row))
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            if let days = row.lowDaysLeft {
                Button {
                    reorderTarget = SupplementIntakeStore.supplement(id: row.dose.supplementID, name: row.dose.name, in: modelContext)
                } label: {
                    KitchenTag(
                        text: days <= 0 ? "Out" : "\(days)d left",
                        tint: days <= 0 ? Tide.danger : Tide.Kitchen.warn
                    )
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.dose.name) running low, reorder")
            }
        }
    }

    private func detailText(_ row: SupplementBoardRow) -> String {
        if let takenAt = row.takenAt {
            return "Taken \(takenAt.formatted(date: .omitted, time: .shortened))"
        }
        let dose = row.dose.dosePerServing
        return dose.isEmpty ? row.dose.timeLabel : "\(dose) · \(row.dose.timeLabel)"
    }

    private func checkButton(_ row: SupplementBoardRow) -> some View {
        Button {
            withAnimation(Tide.lively) {
                viewModel.toggleSupplementTakenWithUndo(
                    supplementID: row.dose.supplementID,
                    name: row.dose.name,
                    modelContext: modelContext
                )
            }
            if !row.isTaken {
                HapticManager.success()
            }
        } label: {
            KitchenCheck(checked: row.isTaken, size: Tide.s10)
                .frame(width: Tide.hit, height: Tide.hit)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.isTaken ? "\(row.dose.name) taken, tap to undo" : "Mark \(row.dose.name) taken")
        .accessibilityIdentifier("supplementCheck.\(row.dose.name)")
    }
}
