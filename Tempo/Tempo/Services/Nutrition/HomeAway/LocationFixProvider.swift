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
    private var authContinuation: CheckedContinuation<Bool, Never>?
    private var fixContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    private var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    func fixIfAuthorized(timeout: TimeInterval = 3) async -> CLLocation? {
        guard isAuthorized, fixContinuation == nil else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finishFix(nil)
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
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        default:
            return false
        }
    }

    private func finishFix(_ location: CLLocation?) {
        guard let continuation = fixContinuation else {
            return
        }
        fixContinuation = nil
        continuation.resume(returning: location)
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
                break
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
