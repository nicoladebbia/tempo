//
// SupplementReorderSheet.swift
// Tempo
//
// Opened from `SupplementReorderBanner` (or the shelf) for one low-stock
// supplement: shows the estimate, lets the user add it to this week's
// grocery list (`PantryGroceryBridge`) or confirm they already restocked
// (resets the count + starts a new reorder-alert cycle), or open
// `SupplementPicksView` for better products and nearby shops.
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI

struct SupplementReorderSheet: View {
    @Bindable var supplement: Supplement

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var addedToList = false
    @State
    private var restocked = false

    private var recentLogs: [SupplementIntakeLog] {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -SupplementReorderService.intakeWindowDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<SupplementIntakeLog>(
            predicate: #Predicate<SupplementIntakeLog> { $0.day >= windowStart }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var daysLeft: Int? {
        SupplementReorderService.daysLeft(for: supplement, recentLogs: recentLogs)
    }

    @Environment(\.tideMood)
    private var mood

    private var isLow: Bool {
        guard let daysLeft else { return false }
        return daysLeft <= SupplementReorderService.lowStockThresholdDays
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tide.s4) {
                    stockCard
                    NavigationLink {
                        SupplementPicksView(supplement: supplement)
                    } label: {
                        HStack(spacing: Tide.s3) {
                            Label("Better products & where to buy", systemImage: "checkmark.seal")
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                            Spacer(minLength: Tide.s2)
                            Image(systemName: "chevron.right")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                        .tideCard(padding: Tide.s4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollIndicators(.hidden)
            // Two ways to deal with it, under the thumb: the main one filled, the other glass.
            .kitchenBottomBar {
                VStack(spacing: Tide.s2) {
                    Text(
                        supplement.servingsPerContainer != nil
                            ? "Restocking adds a full container to what's left and starts a fresh low-stock check."
                            : "Set servings per container in this supplement's edit screen first, so a restock can update the count."
                    )
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Button {
                        addToGroceryList()
                    } label: {
                        Label(
                            addedToList ? "Added to grocery list" : "Add to grocery list",
                            systemImage: addedToList ? "checkmark.circle.fill" : "cart.badge.plus"
                        )
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.kitchenBar)
                    .disabled(addedToList)
                    .accessibilityIdentifier("supplementReorderAddToList")
                    Button {
                        markRestocked()
                    } label: {
                        Label(
                            restocked ? "Restocked" : "I already restocked",
                            systemImage: restocked ? "checkmark.circle.fill" : "shippingbox"
                        )
                        .frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.tideGlass)
                    .disabled(restocked)
                    .accessibilityIdentifier("supplementReorderRestocked")
                }
            }
            .animation(Tide.snap, value: addedToList)
            .animation(Tide.snap, value: restocked)
            .navigationTitle(supplement.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .kitchenSheet()
    }

    /// The answer first: how long it lasts, as a figure and a bar of what is left in the container.
    private var stockCard: some View {
        let tone = isLow ? (daysLeft == 0 ? Tide.danger : Tide.Kitchen.warn) : Tide.text
        return VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(spacing: Tide.s3) {
                TideIconTile(systemName: supplement.kind.icon, size: Tide.Kitchen.tile)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    if let brand = supplement.brand, !brand.isEmpty {
                        Text(brand).tideLabel(Tide.text3)
                    }
                    Text(supplement.name)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                }
            }
            VStack(alignment: .leading, spacing: Tide.s2) {
                TideSectionLabel(title: "Estimated time left", trailing: isLow ? "Reorder soon" : nil)
                if let daysLeft {
                    TideNumber(
                        daysLeft <= 0 ? "Out" : "~\(daysLeft)",
                        unit: daysLeft <= 0 ? nil : (daysLeft == 1 ? "day" : "days"),
                        size: Tide.numeralL, relativeTo: .largeTitle, color: tone
                    )
                } else {
                    TideNumber("Unknown", size: Tide.numeralM, relativeTo: .title, color: Tide.text2)
                }
                if let per = supplement.servingsPerContainer, per > 0, supplement.servingsRemaining > 0 {
                    TideLevelBar(
                        progress: min(supplement.servingsRemaining / per, 1),
                        color: isLow ? Tide.Kitchen.warn : mood.accent,
                        height: Tide.bar
                    )
                    .accessibilityHidden(true)
                }
                Text(supplement.servingsRemaining > 0 ? "\(Int(supplement.servingsRemaining)) servings left in the container" : "Left in container: unknown")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            .accessibilityElement(children: .combine)
            Text("Estimated from how often you've actually marked it taken over the last \(SupplementReorderService.intakeWindowDays) days.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tideCard()
    }

    private func addToGroceryList() {
        _ = try? PantryGroceryBridge.addToCurrentGroceryList(
            canonicalName: supplement.name,
            displayName: supplement.name,
            quantity: 1,
            unit: .pieces,
            modelContext: modelContext
        )
        addedToList = true
        HapticManager.notification(.success)
    }

    private func markRestocked() {
        // Unknown container size → nothing to add; don't pretend it worked.
        guard SupplementReorderService.restock(supplement) else {
            HapticManager.notification(.warning)
            return
        }
        try? modelContext.save()
        restocked = true
        HapticManager.notification(.success)
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }
}
