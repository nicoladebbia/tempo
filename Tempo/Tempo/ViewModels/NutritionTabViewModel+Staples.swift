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
    /// Persisted skip/done state of the "Track your staples" prompt.
    var prompt = StaplesPromptMachine()
    /// Suggestions the user answered "No" to.
    var declined: Set<String> = []
}

// MARK: - ViewModel extension

extension NutritionTabViewModel {
    /// Suggestions for this user: diet/allergy-safe ones only.
    var stapleSuggestions: [(canonicalName: String, displayName: String)] {
        // Re-read the profile: the cached one can be nil (before load) or stale
        // (edited in Fuel setup since), and a stale filter shows allergens.
        var profile = dietaryProfile
        if let context = pantryModelContext {
            profile = (try? context.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first ?? profile
        }
        return PantryStaple.suggestions(for: StapleDietFilter(profile: profile))
    }

    func loadStaplePromptState(store: StaplesPromptStore = StaplesPromptStore()) {
        stapleState.prompt = store.machine
        stapleState.declined = store.declined
    }

    func applyStapleEvent(_ event: StaplesPromptEvent, store: StaplesPromptStore = StaplesPromptStore()) {
        stapleState.prompt.apply(event)
        store.machine = stapleState.prompt
    }

    /// Yes / No on one suggestion. Yes tracks it as "have"; No stops it being
    /// offered again (and untracks it if it was).
    func answerStaple(_ suggestion: (canonicalName: String, displayName: String), have: Bool, store: StaplesPromptStore = StaplesPromptStore()) {
        var declined = stapleState.declined
        if have {
            declined.remove(suggestion.canonicalName)
            addStaple(canonicalName: suggestion.canonicalName, displayName: suggestion.displayName)
        } else {
            declined.insert(suggestion.canonicalName)
            if let existing = stapleState.staples.first(where: { $0.canonicalName == FoodCanonicalizer.canonicalize(suggestion.canonicalName) }) {
                deleteStaple(existing)
            }
        }
        stapleState.declined = declined
        store.declined = declined
    }

    func reloadStaples() {
        guard let service = stapleService else {
            return
        }
        do {
            stapleState.staples = try service.fetchAll()
            stapleState.shouldOfferOnboarding = try service.shouldOfferOnboarding()
            // People who already track staples (from before this prompt
            // existed) are never nagged: settle it as done once.
            let store = StaplesPromptStore()
            if !store.hasStoredPhase, !stapleState.staples.isEmpty {
                applyStapleEvent(.complete, store: store)
            }
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
                let restock = PantryGroceryBridge.restockDefault(canonicalName: staple.canonicalName)
                try? PantryGroceryBridge.addToCurrentGroceryList(
                    canonicalName: staple.canonicalName,
                    displayName: staple.displayName,
                    quantity: restock.quantity,
                    unit: restock.unit,
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
