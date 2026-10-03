//
// LocationFixProvider.swift
// Tempo
//
// A one-shot location fix for the review sheet. NEVER prompts: it only reads a
// fix when the user already granted location (the one place that asks is
// HomeLocationSettingView). Injected through an EnvironmentKey so tests and
// previews can fake it.
//

import CoreLocation
import SwiftUI

@MainActor
protocol LocationFixProviding: AnyObject {
    /// A fresh fix, or nil when location isn't authorized, fails or times out.
    func fixIfAuthorized(timeout: TimeInterval) async -> CLLocation?
    /// Asks for location permission (only called from the Set-home screen).
    func requestPermission() async -> Bool
}

@MainActor
final class CoreLocationFixProvider: NSObject, LocationFixProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuations: [CheckedContinuation<Bool, Never>] = []
    private var fixWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    /// Identifies the in-flight request so a stale timeout can't end a newer one.
    private var requestID = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    private var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// Callers arriving while a request is in flight join it.
    func fixIfAuthorized(timeout: TimeInterval = 3) async -> CLLocation? {
        guard isAuthorized else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let startsRequest = fixWaiters.isEmpty
            fixWaiters.append(continuation)
            guard startsRequest else {
                return
            }
            requestID += 1
            let id = requestID
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                if self?.requestID == id {
                    self?.finishFix(nil)
                }
            }
        }
    }

    func requestPermission() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse,
             .authorizedAlways:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                let first = authContinuations.isEmpty
                authContinuations.append(continuation)
                if first {
                    manager.requestWhenInUseAuthorization()
                }
            }
        default:
            return false
        }
    }

    private func finishFix(_ location: CLLocation?) {
        let waiters = fixWaiters
        fixWaiters = []
        requestID += 1
        // Ignore a stale fix (an abandoned request answering late).
        let fresh = location.flatMap { abs($0.timestamp.timeIntervalSinceNow) < 60 ? $0 : nil }
        for waiter in waiters {
            waiter.resume(returning: fresh)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard !self.authContinuations.isEmpty else {
                return
            }
            let granted: Bool
            switch status {
            case .authorizedWhenInUse,
                 .authorizedAlways:
                granted = true
            case .denied,
                 .restricted:
                granted = false
            default:
                return
            }
            let waiting = self.authContinuations
            self.authContinuations = []
            for continuation in waiting {
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finishFix(last) }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        Task { @MainActor in self.finishFix(nil) }
    }
}

// MARK: - Environment

private struct LocationFixProviderKey: EnvironmentKey {
    /// Built lazily on first read, which always happens from a view body (main actor).
    nonisolated(unsafe) static let defaultValue: any LocationFixProviding = MainActor.assumeIsolated { CoreLocationFixProvider() }
}

extension EnvironmentValues {
    var locationFixProvider: any LocationFixProviding {
        get { self[LocationFixProviderKey.self] }
        set { self[LocationFixProviderKey.self] = newValue }
    }
}
