//
// NotificationSetupView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import CoreLocation
import SwiftUI
import UserNotifications

// MARK: - Notification Setup View (Onboarding)

// Per STATE_MACHINES.md Section 10 — Request notification permissions. OPTIONAL (strongly encouraged).
// Per BUILD_PLAN step 16.1 — Permission request + intensity selection.

struct NotificationSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    // Retained for the lifetime of the view so the CoreLocation authorization
    // dialog (resolved asynchronously via delegate) isn't torn down mid-prompt.
    @State private var locationAuthorizer = LocationAuthorizer()

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Text("THE DRILL SERGEANT\nNEEDS YOUR ATTENTION.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoAmber)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                benefitRow(icon: "sunrise.fill", text: "Morning briefings")
                benefitRow(icon: "clock.fill", text: "Accountability check-ins")
                benefitRow(icon: "flame.fill", text: "Streak protection alerts")
                benefitRow(icon: "trophy.fill", text: "Achievement celebrations")
                benefitRow(icon: "cloud.sun.fill", text: "Weather-aware hydration & training tips")
            }
            .padding(.horizontal, TempoSpacing.xxl)

            Text("You control exactly what and when.\nAdjust anytime in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Spacer()

            OnboardingPrimaryButton(title: "ENABLE NOTIFICATIONS", enabled: true) {
                Task {
                    let center = UNUserNotificationCenter.current()
                    let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
                    viewModel.notificationsGranted = granted ?? false
                    // Also request location here (powers the weather tips above).
                    // No-op if already determined; degrades silently if denied.
                    await locationAuthorizer.requestWhenInUseIfNeeded()
                    viewModel.advance()
                }
            }

            OnboardingSkipButton { viewModel.skip() }

            Spacer().frame(height: TempoSpacing.xxxl)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoAmber)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - LocationAuthorizer

/// Requests "When In Use" location authorization once, during onboarding.
/// Retained by the hosting view so the async permission dialog (delivered via
/// delegate callback) survives until the user responds. Returns when the
/// authorization status has resolved; the caller does not need the result —
/// the dashboard later fetches location only if access ended up granted.
@MainActor
final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    /// Triggers the system prompt only when status is `.notDetermined`.
    /// Resolves immediately (no prompt) if the user already decided.
    func requestWhenInUseIfNeeded() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Fires once the user responds (status leaves .notDetermined).
        guard manager.authorizationStatus != .notDetermined else { return }
        Task { @MainActor in
            self.manager.delegate = nil
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    NotificationSetupView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
