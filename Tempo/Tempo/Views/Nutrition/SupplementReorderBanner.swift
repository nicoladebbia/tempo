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
    @Environment(\.dynamicTypeSize)
    private var typeSize

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
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s2) {
                Image(systemName: "cart.badge.plus")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.Kitchen.warn)
                    .accessibilityHidden(true)
                Text("Running out").tideLabel()
                Spacer()
            }

            VStack(spacing: Tide.s2) {
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
        .tideCard(padding: Tide.s4)
        .overlay(
            RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                .strokeBorder(Tide.Kitchen.warn.opacity(0.30), lineWidth: 1)
        )
        .sheet(item: $reorderTarget) { supplement in
            SupplementReorderSheet(supplement: supplement)
        }
    }

    private func row(for supplement: Supplement, daysLeft: Int) -> some View {
        // At the accessibility sizes the tag drops under the name, so the name keeps the full width.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return layout {
            Text(supplement.name)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            if !typeSize.isAccessibilitySize {
                Spacer()
            }
            HStack(spacing: Tide.s2) {
                KitchenTag(
                    text: daysLeft <= 0 ? "Out" : "\(daysLeft)d left",
                    tint: daysLeft <= 0 ? Tide.danger : Tide.Kitchen.warn
                )
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
    }
}
