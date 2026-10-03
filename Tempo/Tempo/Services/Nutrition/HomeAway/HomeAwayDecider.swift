//
// HomeAwayDecider.swift
// Tempo
//
// Pure logic behind "did you eat this at home?": given a location fix and the
// saved home spot, decide at home / away / unknown, and which origin to
// pre-select on the review sheet. No I/O, so it is fully unit-testable.
//

import CoreLocation
import Foundation

/// Where a logged meal came from. `kitchen` takes the foods off the pantry;
/// `out` is eating out (the pantry is left alone).
enum MealOrigin: String, Codable, Sendable, CaseIterable {
    case kitchen
    case out
}

enum HomeAwayDecider {
    /// Home radius in metres.
    static let defaultRadius: CLLocationDistance = 150
    /// A fix worse than this says nothing about being home.
    static let maxUsableAccuracy: CLLocationAccuracy = 500
    /// How much of the fix's own uncertainty counts in the user's favour.
    static let accuracyAllowanceCap: CLLocationDistance = 100

    /// true = at home, false = away, nil = can't tell (no fix, no home set, or
    /// a fix too imprecise to trust).
    static func isAtHome(
        fix: CLLocation?,
        home: HomeLocation?,
        radius: CLLocationDistance = defaultRadius
    ) -> Bool? {
        guard let fix, let home else {
            return nil
        }
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxUsableAccuracy else {
            return nil
        }
        let distance = fix.distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude))
        return distance <= radius + min(fix.horizontalAccuracy, accuracyAllowanceCap)
    }

    /// What to pre-select: at home → kitchen, away → out, unknown → whatever
    /// the user chose last time (kitchen when they never chose).
    static func defaultOrigin(atHome: Bool?, remembered: MealOrigin?) -> MealOrigin {
        switch atHome {
        case true?: .kitchen
        case false?: .out
        case nil: remembered ?? .kitchen
        }
    }
}
