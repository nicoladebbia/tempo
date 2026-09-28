//
// SupplementPicksService.swift
// Tempo
//
// Backs SupplementPicksView: fetches curated/AI-fallback product picks for a
// shelf supplement (GET /v1/supplements/picks/:kind) and finds nearby
// vitamin/supplement stores via MapKit (no backend call — same
// Apple-Maps-is-free pattern as NearbyRestaurants).
//

import CoreLocation
import Foundation
import MapKit

// MARK: - SupplementPicksService

struct SupplementPicksService: Sendable {
    let apiClient: APIClient

    func fetchPicks(kind: SupplementKind, name: String) async throws -> SupplementPicksDTO {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryItems = trimmedName.isEmpty ? nil : [URLQueryItem(name: "name", value: trimmedName)]
        return try await apiClient.request(.supplementPicks(kind: kind), queryItems: queryItems)
    }
}

// MARK: - NearbyStoreResult

/// Lightweight, testable result shape — deliberately NOT `MKMapItem` (which
/// can't be constructed in a unit test without a live MapKit search). The
/// view reconstructs an `MKMapItem` from lat/lon only when the user taps
/// "open in Maps".
struct NearbyStoreResult: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
}

// MARK: - SupplementNearbyStores

enum SupplementNearbyStores {
    /// Chains worth checking for supplements near the user, per Nicola's
    /// spec — general vitamin/supplement shops plus grocery/pharmacy chains
    /// that commonly stock them.
    static let chainQueries = [
        "GNC",
        "The Vitamin Shoppe",
        "Whole Foods Market",
        "Walgreens",
        "CVS Pharmacy",
        "Costco",
        "Sprouts Farmers Market",
    ]

    /// Searches all chains in parallel under one shared deadline (same
    /// pattern as `NearbyRestaurants.around` — whatever hasn't answered by
    /// the deadline is dropped rather than blocking the UI). Returns sorted,
    /// deduped results within `radiusMeters` of the given coordinate.
    @MainActor
    static func around(
        latitude: Double,
        longitude: Double,
        limit: Int = 10,
        radiusMeters: Double = 8000,
        deadline: Duration = .seconds(4)
    ) async -> [NearbyStoreResult] {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )

        enum Answer: Sendable {
            case found([NearbyStoreResult])
            case failed
            case deadline
        }

        let raw: [NearbyStoreResult] = await withTaskGroup(of: Answer.self) { group in
            for query in chainQueries {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = query
                    request.region = region
                    request.resultTypes = .pointOfInterest
                    guard let items = try? await MKLocalSearch(request: request).start().mapItems else {
                        return .failed
                    }
                    let origin = CLLocation(latitude: latitude, longitude: longitude)
                    let results: [NearbyStoreResult] = items.compactMap { item in
                        guard let name = item.name else {
                            return nil
                        }
                        let coordinate = item.placemark.coordinate
                        let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                            .distance(from: origin)
                        return NearbyStoreResult(
                            id: "\(name)|\(coordinate.latitude)|\(coordinate.longitude)",
                            name: name,
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            distanceMeters: distance
                        )
                    }
                    return .found(results)
                }
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return .deadline
            }

            var out: [NearbyStoreResult] = []
            var pending = chainQueries.count
            loop: while pending > 0, let answer = await group.next() {
                switch answer {
                case .deadline:
                    break loop
                case .failed:
                    pending -= 1
                case let .found(results):
                    out.append(contentsOf: results)
                    pending -= 1
                }
            }
            group.cancelAll()
            return out
        }

        return sortedDeduped(raw, limit: limit)
    }

    /// Pure, unit-testable: nearest first, with same-store duplicates
    /// dropped. MKLocalSearch can return the same physical store from two
    /// overlapping chain queries (e.g. a Whole Foods with an in-store
    /// vitamin counter matching more than one query) — a duplicate is same
    /// name (case-insensitive) within ~50m of an already-kept result.
    static func sortedDeduped(_ results: [NearbyStoreResult], limit: Int) -> [NearbyStoreResult] {
        let sorted = results.sorted { $0.distanceMeters < $1.distanceMeters }
        var kept: [NearbyStoreResult] = []
        for candidate in sorted {
            let isDuplicate = kept.contains { existing in
                existing.name.caseInsensitiveCompare(candidate.name) == .orderedSame
                    && approximateDistanceMeters(existing, candidate) < 50
            }
            guard !isDuplicate else {
                continue
            }
            kept.append(candidate)
            if kept.count >= limit {
                break
            }
        }
        return kept
    }

    private static func approximateDistanceMeters(_ a: NearbyStoreResult, _ b: NearbyStoreResult) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

// MARK: - SupplementLocationProvider

/// One-shot, ACTIVE location request (unlike the passive
/// `OneShotLocationProvider` in DashboardViewModel) — this triggers the
/// system permission prompt when not yet determined, since the user tapped
/// into the Nearby section specifically to find stores. Never runs eagerly.
@MainActor
final class SupplementLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Bool, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    var isPermanentlyDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// Requests when-in-use permission if undetermined, then returns a
    /// single location fix, or nil if denied/failed.
    func requestLocation() async -> CLLocation? {
        guard await ensureAuthorized() else {
            return nil
        }
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func ensureAuthorized() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse,
             .authorizedAlways:
            true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                self.authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        default:
            false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard let continuation = self.authContinuation else {
                return
            }
            switch status {
            case .authorizedWhenInUse,
                 .authorizedAlways:
                self.authContinuation = nil
                continuation.resume(returning: true)
            case .denied,
                 .restricted:
                self.authContinuation = nil
                continuation.resume(returning: false)
            default:
                break // still not determined — wait for the next callback
            }
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: locations.last)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}
