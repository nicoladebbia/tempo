//
// MealOriginPicker.swift
// Tempo
//
// Compact "Kitchen / Ate out" choice for the logging surfaces that don't use
// the review sheet's draft (scan product page, full Log Meal sheet). Same
// rules: one location fix only when permission is already granted (never
// prompts), pre-selects from home / away, falls back to the last choice, and a
// manual pick sticks.
//

import CoreLocation
import SwiftData
import SwiftUI

struct MealOriginPicker: View {
    @Binding
    var origin: MealOrigin
    /// The foods about to be logged (drives the pantry preview).
    let foods: [PlannedFood]
    /// Owned by the parent so a manual pick survives this view being rebuilt.
    @Binding
    var pickedByHand: Bool

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.locationFixProvider)
    private var locationProvider

    @State
    private var atHome: Bool?
    @State
    private var home: HomeLocation? = HomeLocationStore().home
    @State
    private var showHomeSetting = false

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Picker("Where from", selection: Binding(
                get: { origin },
                set: { origin = $0; pickedByHand = true }
            )) {
                Text("Kitchen").tag(MealOrigin.kitchen)
                Text("Ate out").tag(MealOrigin.out)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("mealOrigin")
            if let headline {
                Text(headline)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .accessibilityIdentifier("mealOriginHeadline")
            }
            Text(detail)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mealOriginDetail")
            Button(home == nil ? "Set home" : "Change home") { showHomeSetting = true }
                .font(.tempoCaption1)
                .accessibilityIdentifier("mealOriginSetHome")
        }
        .task { await refresh() }
        .sheet(isPresented: $showHomeSetting, onDismiss: { Task { await refresh() } }) {
            HomeLocationSettingView()
        }
    }

    private var headline: String? {
        guard home != nil else {
            return nil
        }
        switch atHome {
        case true?: return origin == .kitchen ? "You're home. From your kitchen?" : "You're home. Logged as eaten out."
        case false?: return origin == .out ? "Not home. Logged as eaten out." : "Not home, but from your kitchen."
        case nil: return "Can't tell where you are. Using your last choice."
        }
    }

    private var detail: String {
        guard origin == .kitchen else {
            return "Your pantry stays as it is."
        }
        let lines = PantryDecrementService.preview(foods: foods, modelContext: modelContext)
        return lines.isEmpty
            ? "Nothing in your pantry matches. Nothing comes off."
            : "Comes off your pantry: " + lines.map { "\($0.displayName) \($0.amountText)" }.joined(separator: ", ")
    }

    private func refresh() async {
        let store = HomeLocationStore()
        home = store.home
        var fix: CLLocation?
        if home != nil {
            fix = await locationProvider.fixIfAuthorized(timeout: 3)
        }
        atHome = HomeAwayDecider.isAtHome(fix: fix, home: home)
        if !pickedByHand {
            origin = HomeAwayDecider.defaultOrigin(atHome: atHome, remembered: store.lastOrigin)
        }
    }
}
