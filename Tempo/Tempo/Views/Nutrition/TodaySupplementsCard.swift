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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            header(board)
            ForEach(board.sections) { section in
                VStack(alignment: .leading, spacing: 0) {
                    Label(section.period.title.uppercased(), systemImage: section.period.icon)
                        .font(.tempoModuleTag)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .padding(.bottom, TempoSpacing.xs)
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().overlay(Color.tempoDivider)
                        }
                        rowView(row)
                    }
                }
            }
            if !board.skipped.isEmpty {
                Text("Skipping today: " + board.skipped.map(\.name).joined(separator: ", "))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
        .accessibilityIdentifier("today.supplements")
    }

    private func header(_ board: SupplementTodayBoard) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY'S SUPPLEMENTS")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer(minLength: TempoSpacing.sm)
                Text(board.allTaken ? "All taken" : "Taken \(board.takenCount)/\(board.total)")
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(board.allTaken ? Color.tempoSuccess : Color.tempoTextSecondary)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tempoDivider)
                    Capsule()
                        .fill(board.allTaken ? Color.tempoSuccess : Color.tempoSignal)
                        .frame(width: geo.size.width * (board.total == 0 ? 0 : Double(board.takenCount) / Double(board.total)))
                        .animation(TempoAnimation.springMedium, value: board.takenCount)
                }
            }
            .frame(height: 4)
        }
    }

    private func rowView(_ row: SupplementBoardRow) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Button {
                viewModel.openSupplement(row.dose.supplementID)
            } label: {
                HStack(spacing: TempoSpacing.md) {
                    Image(systemName: row.dose.kind.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(row.isTaken ? Color.tempoTextTertiary : Color.tempoSignal)
                        .frame(width: 36, height: 36)
                        .background(Color.tempoBgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.dose.name)
                            .font(.tempoBodyBold)
                            .foregroundStyle(row.isTaken ? Color.tempoTextSecondary : Color.tempoTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        detailLine(row)
                        if let macros = row.macrosLine {
                            Text(macros)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                                .lineLimit(1)
                        }
                    }
                    .opacity(row.isTaken ? 0.7 : 1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.dose.name), \(row.dose.dosePerServing), \(row.dose.timeLabel). Open details")

            checkButton(row)
        }
        .padding(.vertical, TempoSpacing.sm)
    }

    private func detailLine(_ row: SupplementBoardRow) -> some View {
        HStack(spacing: TempoSpacing.xs) {
            Text(detailText(row))
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .lineLimit(1)
            if let days = row.lowDaysLeft {
                Button {
                    reorderTarget = SupplementIntakeStore.supplement(id: row.dose.supplementID, name: row.dose.name, in: modelContext)
                } label: {
                    Text(days <= 0 ? "Out" : "\(days)d left")
                        .font(.tempoCaption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(days <= 0 ? Color.tempoError : Color.tempoAmber)
                        .padding(.horizontal, TempoSpacing.sm)
                        .padding(.vertical, 2)
                        .background((days <= 0 ? Color.tempoError : Color.tempoAmber).opacity(TempoOpacity.o15))
                        .clipShape(Capsule())
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
            withAnimation(TempoAnimation.springMedium) {
                viewModel.toggleSupplementTaken(
                    supplementID: row.dose.supplementID,
                    name: row.dose.name,
                    modelContext: modelContext
                )
            }
            if !row.isTaken {
                HapticManager.success()
            }
        } label: {
            ZStack {
                if row.isTaken {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.tempoTextInverse)
                }
            }
            .frame(width: 44, height: 44)
                .background(row.isTaken ? Color.tempoSuccess : Color.clear)
                .clipShape(Circle())
                .overlay(Circle().stroke(row.isTaken ? Color.clear : Color.tempoBorder, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.isTaken ? "\(row.dose.name) taken, tap to undo" : "Mark \(row.dose.name) taken")
        .accessibilityIdentifier("supplementCheck.\(row.dose.name)")
    }
}
