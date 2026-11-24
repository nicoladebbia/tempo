//
// LocationAuthorizer.swift
// Tempo
//
// Asks for location access ("while using the app") and waits for the answer. Used by the
// onboarding permissions step and by Settings > Connections; it powers the weather tips.
//

import CoreLocation

// MARK: - LocationAuthorizer

/// Retain it for the lifetime of the view that asks, so the CoreLocation authorization dialog
/// (resolved asynchronously via delegate) isn't torn down mid-prompt.
@MainActor
final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    /// Triggers the system prompt only when status is `.notDetermined`.
    /// Resolves immediately (no prompt) if the user already decided.
    func requestWhenInUseIfNeeded() async {
        guard manager.authorizationStatus == .notDetermined else {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Fires once the user responds (status leaves .notDetermined).
        guard manager.authorizationStatus != .notDetermined else {
            return
        }
        Task { @MainActor in
            self.manager.delegate = nil
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
