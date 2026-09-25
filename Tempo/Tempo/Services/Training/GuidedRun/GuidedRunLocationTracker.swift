//
// GuidedRunLocationTracker.swift
// Tempo
//
// Guided run mode — GPS distance/pace for a continuous step (duration or
// distance shape). Requests when-in-use authorization only when a
// continuous step actually starts (never eagerly at app launch), and
// degrades gracefully to "timer only" when denied/restricted — the session
// engine and the rest of the guided-run UI never depend on location being
// available.
//
// `allowsBackgroundLocationUpdates` is set true only while `start()` has an
// active tracking session and turned back off in `stop()`, per Apple's
// "only while genuinely needed" guidance — this is what keeps the run
// tracking while the screen locks. Requires the `location` UIBackgroundMode
// (added to project.yml/Info.plist alongside this feature) and is guarded
// to authorized statuses only, so it never throws on a fresh install that
// hasn't granted location yet.
//

import CoreLocation
import Foundation

// MARK: - GuidedRunLocationTracker

@MainActor
@Observable
final class GuidedRunLocationTracker: NSObject {
    enum AuthorizationOutcome: Equatable {
        case authorized
        case denied
        case notDetermined
    }

    private(set) var distanceMeters: Double = 0
    /// Instantaneous pace, seconds per km — nil until enough motion to be
    /// meaningful (avoids a wild first-sample number).
    private(set) var currentPaceSecondsPerKm: Double?
    private(set) var averagePaceSecondsPerKm: Double?
    private(set) var isAuthorized = false
    private(set) var isTracking = false

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var startDate: Date?
    private var recentSamples: [(date: Date, distance: Double)] = []

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5 // meters
        manager.delegate = self
        isAuthorized = Self.isAuthorizedStatus(manager.authorizationStatus)
    }

    /// Requests when-in-use permission (a no-op if already decided) and, if
    /// authorized, starts updating. Call this when a continuous step
    /// begins — never before.
    func start() {
        distanceMeters = 0
        currentPaceSecondsPerKm = nil
        averagePaceSecondsPerKm = nil
        lastLocation = nil
        startDate = Date()
        recentSamples = []

        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse,
             .authorizedAlways:
            beginUpdating()
        default:
            isAuthorized = false
        }
    }

    func stop() {
        isTracking = false
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    private func beginUpdating() {
        isAuthorized = true
        isTracking = true
        // Background updates only while a run is actually in progress, and
        // only when the app is entitled to it — guarded so a build without
        // the `location` UIBackgroundMode (or an authorization the OS
        // considers insufficient) never trips the CLLocationManager
        // precondition crash.
        if Bundle.main.backgroundModes.contains("location"),
           manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
        {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    private static func isAuthorizedStatus(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }
}

// MARK: CLLocationManagerDelegate

extension GuidedRunLocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.isAuthorized = Self.isAuthorizedStatus(status)
            if self.isAuthorized, self.startDate != nil, !self.isTracking {
                self.beginUpdating()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last, newest.horizontalAccuracy >= 0, newest.horizontalAccuracy < 50 else {
            return
        }
        Task { @MainActor in
            self.consume(newest)
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        // Timer-only fallback — nothing to surface, the guided run UI just
        // won't show a distance/pace row.
    }

    private func consume(_ location: CLLocation) {
        defer { lastLocation = location }
        guard let lastLocation else {
            return
        }
        let delta = location.distance(from: lastLocation)
        guard delta > 0, delta < 200 else { // reject GPS jumps
            return
        }
        distanceMeters += delta

        let now = location.timestamp
        recentSamples.append((date: now, distance: delta))
        // Keep a ~20s rolling window for current pace.
        recentSamples.removeAll { now.timeIntervalSince($0.date) > 20 }
        let windowDistance = recentSamples.reduce(0) { $0 + $1.distance }
        if let firstSample = recentSamples.first {
            let windowSeconds = now.timeIntervalSince(firstSample.date)
            if windowDistance > 0, windowSeconds > 0 {
                currentPaceSecondsPerKm = (windowSeconds / windowDistance) * 1000
            }
        }

        if let startDate {
            let elapsed = now.timeIntervalSince(startDate)
            if distanceMeters > 0, elapsed > 0 {
                averagePaceSecondsPerKm = (elapsed / distanceMeters) * 1000
            }
        }
    }
}

// MARK: - Bundle background modes helper

private extension Bundle {
    var backgroundModes: [String] {
        (object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]) ?? []
    }
}
