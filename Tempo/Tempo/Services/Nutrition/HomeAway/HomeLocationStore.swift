//
// HomeLocationStore.swift
// Tempo
//
// Where "home" is, kept in UserDefaults on THIS device only: never synced,
// never sent to the backend or to the AI. Also remembers the last meal origin
// the user picked, as the fallback when a location fix isn't available.
//

import Foundation

struct HomeLocation: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var label: String?
    var setAt: Date
}

struct HomeLocationStore {
    private let defaults: UserDefaults
    private static let homeKey = "tempo.homeAway.home"
    private static let originKey = "tempo.homeAway.lastOrigin"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var home: HomeLocation? {
        get {
            defaults.data(forKey: Self.homeKey).flatMap { try? JSONDecoder().decode(HomeLocation.self, from: $0) }
        }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.homeKey)
            } else {
                defaults.removeObject(forKey: Self.homeKey)
            }
        }
    }

    var lastOrigin: MealOrigin? {
        get {
            defaults.string(forKey: Self.originKey).flatMap(MealOrigin.init(rawValue:))
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: Self.originKey)
            } else {
                defaults.removeObject(forKey: Self.originKey)
            }
        }
    }

    func setHome(latitude: Double, longitude: Double, label: String?, now: Date = Date()) {
        home = HomeLocation(latitude: latitude, longitude: longitude, label: label, setAt: now)
    }

    func clearHome() {
        home = nil
    }
}
