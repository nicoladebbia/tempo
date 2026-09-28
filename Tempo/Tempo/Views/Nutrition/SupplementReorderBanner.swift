//
// SupplementReorderBanner.swift
// Tempo
//
// "When to buy/reorder" surfaced on the Today tab — a supplement with
// `SupplementReorderService.needsReorder == true` (≤7 days left, estimated
// from the last 14 days of intake logs) gets a row here. Tapping a row opens
// `SupplementReorderSheet` to add it to the grocery list or mark it restocked.
// Hidden entirely when nothing is low. Standalone view (own @Query) so it
// drops into any screen without threading state through a view model.
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI

struct SupplementReorderBanner: View {
    @Environment(\.modelContext)
    private var modelContext

    @Query(
        filter: #Predicate<Supplement> { !$0.isArchived },
        sort: \Supplement.name
    )
    private var supplements: [Supplement]

    @State
    private var reorderTarget: Supplement?

    private var recentLogs: [SupplementIntakeLog] {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -SupplementReorderService.intakeWindowDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<SupplementIntakeLog>(
            predicate: #Predicate<SupplementIntakeLog> { $0.day >= windowStart }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Low-stock items with their estimated days left, soonest first.
    private var lowItems: [(supplement: Supplement, daysLeft: Int)] {
        let logs = recentLogs
        return supplements.compactMap { supplement -> (Supplement, Int)? in
            guard SupplementReorderService.needsReorder(for: supplement, recentLogs: logs) else {
                return nil
            }
            return (supplement, SupplementReorderService.daysLeft(for: supplement, recentLogs: logs) ?? 0)
        }
        .sorted { $0.1 < $1.1 }
    }

    var body: some View {
        if lowItems.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.tempoAmber)
                Text("RUNNING OUT")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
            }

            VStack(spacing: TempoSpacing.sm) {
                ForEach(lowItems, id: \.supplement.id) { item in
                    Button {
                        reorderTarget = item.supplement
                    } label: {
                        row(for: item.supplement, daysLeft: item.daysLeft)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(TempoSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .fill(Color.tempoSurfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .strokeBorder(Color.tempoAmber.opacity(0.30), lineWidth: 1)
        )
        .sheet(item: $reorderTarget) { supplement in
            SupplementReorderSheet(supplement: supplement)
        }
    }

    private func row(for supplement: Supplement, daysLeft: Int) -> some View {
        HStack {
            Text(supplement.name)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Text(daysLeft <= 0 ? "out" : "\(daysLeft)d left")
                .font(.tempoCaption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill((daysLeft <= 0 ? Color.tempoError : Color.tempoAmber).opacity(0.15)))
                .foregroundStyle(daysLeft <= 0 ? Color.tempoError : Color.tempoAmber)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .contentShape(Rectangle())
    }
}
