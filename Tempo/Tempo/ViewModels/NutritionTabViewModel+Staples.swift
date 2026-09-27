//
// NutritionTabViewModel+Staples.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation
import SwiftData

// MARK: - NutritionStapleState

@MainActor
@Observable
final class NutritionStapleState {
    var staples: [PantryStaple] = []
    /// `true` when the staples list is empty and the onboarding checklist
    /// (`PantryStapleOnboardingSheet`) should be offered on first open.
    var shouldOfferOnboarding: Bool = false
    var loadError: String?
}

// MARK: - ViewModel extension

extension NutritionTabViewModel {
    func reloadStaples() {
        guard let service = stapleService else {
            return
        }
        do {
            stapleState.staples = try service.fetchAll()
            stapleState.shouldOfferOnboarding = try service.shouldOfferOnboarding()
            stapleState.loadError = nil
        } catch {
            stapleState.loadError = error.localizedDescription
        }
    }

    /// One-tap cycle from the Staples section row: have → running low →
    /// out → have. Crossing INTO `.runningLow` or `.out` pushes the staple
    /// onto the current week's grocery list (idempotent — bumps the
    /// existing row instead of duplicating if it's already there). Cycling
    /// back to `.have` does NOT remove it from an already-generated list;
    /// the user checks it off like anything else once bought.
    func cycleStapleStatus(_ staple: PantryStaple) {
        guard let service = stapleService else {
            return
        }
        do {
            let newStatus = try service.cycleStatus(staple)
            if newStatus.needsRestock, let context = pantryModelContext {
                try? PantryGroceryBridge.addToCurrentGroceryList(
                    canonicalName: staple.canonicalName,
                    displayName: staple.displayName,
                    quantity: 1,
                    unit: .pieces,
                    modelContext: context
                )
            }
        } catch {
            stapleState.loadError = error.localizedDescription
        }
        reloadStaples()
    }

    func addStaple(canonicalName: String, displayName: String) {
        guard let service = stapleService else {
            return
        }
        do {
            _ = try service.addStaple(canonicalName: canonicalName, displayName: displayName, status: .have)
        } catch {
            stapleState.loadError = error.localizedDescription
        }
        reloadStaples()
    }

    /// Onboarding checklist commit — adds every picked suggestion as
    /// `.have` (the user is confirming "yes I keep this stocked", not
    /// reporting it's out).
    func seedSelectedStaples(_ picks: [(canonicalName: String, displayName: String)]) {
        guard let service = stapleService, !picks.isEmpty else {
            return
        }
        do {
            try service.addStaples(picks)
        } catch {
            stapleState.loadError = error.localizedDescription
        }
        reloadStaples()
    }

    func deleteStaple(_ staple: PantryStaple) {
        guard let service = stapleService else {
            return
        }
        do {
            try service.delete(staple)
        } catch {
            stapleState.loadError = error.localizedDescription
        }
        reloadStaples()
    }
}
