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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Left in container") {
                        Text(supplement.servingsRemaining > 0 ? "\(Int(supplement.servingsRemaining)) servings" : "Unknown")
                    }
                    if let daysLeft {
                        LabeledContent("Estimated time left") {
                            Text(daysLeft <= 0 ? "Out" : "~\(daysLeft) day\(daysLeft == 1 ? "" : "s")")
                                .foregroundStyle(daysLeft <= SupplementReorderService.lowStockThresholdDays ? Color.tempoError : Color
                                    .tempoTextPrimary)
                        }
                    }
                } footer: {
                    Text(
                        "Estimated from how often you've actually marked it taken over the last \(SupplementReorderService.intakeWindowDays) days."
                    )
                }

                Section {
                    Button {
                        addToGroceryList()
                    } label: {
                        Label(
                            addedToList ? "Added to grocery list" : "Add to grocery list",
                            systemImage: addedToList ? "checkmark.circle.fill" : "cart.badge.plus"
                        )
                    }
                    .disabled(addedToList)

                    Button {
                        markRestocked()
                    } label: {
                        Label(
                            restocked ? "Restocked" : "I already restocked",
                            systemImage: restocked ? "checkmark.circle.fill" : "shippingbox"
                        )
                    }
                    .disabled(restocked)
                } footer: {
                    Text(
                        supplement.servingsPerContainer != nil
                            ? "Restocking adds a full container to what's left and starts a fresh low-stock check."
                            : "Restocking starts a fresh low-stock check. Add servings per container to keep count."
                    )
                }

                Section {
                    NavigationLink {
                        SupplementPicksView(supplement: supplement)
                    } label: {
                        Label("Better products & where to buy", systemImage: "checkmark.seal")
                    }
                }
            }
            .navigationTitle(supplement.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
        SupplementReorderService.restock(supplement)
        try? modelContext.save()
        restocked = true
        HapticManager.notification(.success)
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }
}
