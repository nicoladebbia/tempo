//
// ClearSkinFocusSetting.swift
// Tempo
//
// Opt-in toggle for the clear-skin / low-dairy layer of the meal-plan prompt
// (low glycemic load, no added sweeteners, minimize dairy). It used to be
// injected into EVERY user's plan unconditionally. Stored in UserDefaults —
// no SwiftData model change. Edited from AI Meals settings.
//
// Default OFF for new users. Existing installs keep today's behavior via a
// one-time migration: key unset + an existing DietaryProfile + an already
// generated meal plan → ON. The plan check is what separates an existing
// install from a brand-new user whose FIRST generate happens right after they
// create their profile. It runs at app launch (ContentView) and again lazily
// on first read, from the generator and the settings screen.
//

import Foundation
import SwiftData

enum ClearSkinFocusSetting {
    static let key = "nutrition.clearSkinFocus.enabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }

    /// Pure migration decision. No-op once the key has any value.
    static func migrateIfNeeded(
        hasExistingProfile: Bool,
        hasExistingPlan: Bool,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: key) == nil else {
            return
        }
        defaults.set(hasExistingProfile && hasExistingPlan, forKey: key)
    }

    /// Run the one-time migration against the store, then return the value.
    @MainActor
    @discardableResult
    static func resolve(modelContext: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: key) == nil {
            let profiles = (try? modelContext.fetchCount(FetchDescriptor<DietaryProfile>())) ?? 0
            let plans = (try? modelContext.fetchCount(FetchDescriptor<WeeklyMealPlan>())) ?? 0
            migrateIfNeeded(hasExistingProfile: profiles > 0, hasExistingPlan: plans > 0, defaults: defaults)
        }
        return isEnabled(defaults: defaults)
    }
}
