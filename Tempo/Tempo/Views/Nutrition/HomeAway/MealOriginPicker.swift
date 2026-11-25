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
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var tileLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            // Side by side; stacked at accessibility sizes so neither name shrinks.
            tileLayout {
                tile(.kitchen, title: String(localized: "Kitchen"), icon: "refrigerator.fill")
                tile(.out, title: String(localized: "Ate out"), icon: "takeoutbag.and.cup.and.straw.fill")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Where from")
            .accessibilityIdentifier("mealOrigin")
            VStack(alignment: .leading, spacing: Tide.s1) {
                if let headline {
                    Text(headline)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("mealOriginHeadline")
                }
                Text(detail)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mealOriginDetail")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Tide.snap, value: origin)
            Button {
                showHomeSetting = true
            } label: {
                Label(home == nil ? String(localized: "Set home") : String(localized: "Change home"), systemImage: "house")
                    .font(Tide.caption)
                    .foregroundStyle(mood.accent)
                    .frame(minHeight: Tide.hit, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mealOriginSetHome")
        }
        .task { await refresh() }
        .sheet(isPresented: $showHomeSetting, onDismiss: { Task { await refresh() } }) {
            HomeLocationSettingView()
        }
    }

    /// One of the two answers: soft fill, accent ring when it is the one picked.
    private func tile(_ value: MealOrigin, title: String, icon: String) -> some View {
        let selected = origin == value
        return Button {
            HapticManager.selection()
            origin = value
            pickedByHand = true
        } label: {
            Label(title, systemImage: icon)
                .font(Tide.bodyStrong)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .frame(maxWidth: .infinity)
                .fuelChoice(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var headline: String? {
        guard home != nil else {
            return nil
        }
        switch atHome {
        case true?: return origin == .kitchen ? String(localized: "You're home. From your kitchen?") : String(localized: "You're home. Logged as eaten out.")
        case false?: return origin == .out ? String(localized: "Not home. Logged as eaten out.") : String(localized: "Not home, but from your kitchen.")
        case nil: return String(localized: "Can't tell where you are. Using your last choice.")
        }
    }

    private var detail: String {
        guard origin == .kitchen else {
            return String(localized: "Your pantry stays as it is.")
        }
        let lines = PantryDecrementService.preview(foods: foods, modelContext: modelContext)
        guard !lines.isEmpty else {
            return String(localized: "Nothing in your pantry matches. Nothing comes off.")
        }
        let list = lines.map { "\($0.displayName) \($0.amountText)" }.joined(separator: ", ")
        return String(localized: "Comes off your pantry: \(list)")
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
