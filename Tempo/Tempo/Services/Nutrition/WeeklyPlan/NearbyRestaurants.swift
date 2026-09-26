//
// NearbyRestaurants.swift
// Tempo
//
// Restaurants around each routine place (Apple Maps, free) so the planner can
// suggest a better-fitting spot than the usual one.
//

import Foundation
import MapKit

enum NearbyRestaurants {
    /// Place name → up to `limit` restaurant/café names within ~1 km. Places
    /// without coordinates are skipped. All places are searched at once under
    /// one shared `deadline`; whatever hasn't answered by then is dropped — the
    /// plan never waits on Maps (the Sunday "Yes" runs on a short background
    /// budget).
    @MainActor
    static func around(_ routine: WeeklyRoutine?, limit: Int = 12, deadline: Duration = .seconds(4)) async -> [String: [String]] {
        guard let routine else {
            return [:]
        }
        let placesWithMealsOut = Set(routine.days.flatMap(\.events).filter { $0.kind == .mealOut }.compactMap(\.placeID))
        let targets: [(name: String, latitude: Double, longitude: Double)] = routine.places.compactMap { place in
            guard placesWithMealsOut.contains(place.id), let latitude = place.latitude, let longitude = place.longitude else {
                return nil
            }
            return (place.name, latitude, longitude)
        }
        guard !targets.isEmpty else {
            return [:]
        }
        enum Answer: Sendable {
            case found(place: String, names: [String])
            case failed
            case deadline
        }
        return await withTaskGroup(of: Answer.self) { group in
            for target in targets {
                group.addTask {
                    let request = MKLocalPointsOfInterestRequest(
                        center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                        radius: 1000
                    )
                    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery])
                    guard let items = try? await MKLocalSearch(request: request).start().mapItems else {
                        return .failed
                    }
                    return .found(place: target.name, names: items.compactMap(\.name))
                }
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return .deadline
            }
            var out: [String: [String]] = [:]
            var pending = targets.count
            loop: while pending > 0, let answer = await group.next() {
                switch answer {
                case .deadline:
                    break loop
                case .failed:
                    pending -= 1
                case let .found(place, names):
                    var seen = Set<String>()
                    out[place] = names.filter { seen.insert($0.lowercased()).inserted }.prefix(limit).map(\.self)
                    pending -= 1
                }
            }
            group.cancelAll()
            return out
        }
    }
}
