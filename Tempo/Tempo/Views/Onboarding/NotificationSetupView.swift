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

// MARK: - NotificationSetupView

// Per STATE_MACHINES.md Section 10 — Request notification permissions. OPTIONAL (strongly encouraged).
// Per BUILD_PLAN step 16.1 — Permission request + intensity selection.
//
// The step shows what you would get: three sample banners drop in one after
// another, then the list of everything the drill sergeant can send.

struct NotificationSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var shown = 0

    /// Retained for the lifetime of the view so the CoreLocation authorization
    /// dialog (resolved asynchronously via delegate) isn't torn down mid-prompt.
    @State private var locationAuthorizer = LocationAuthorizer()

    private struct Sample: Hashable {
        let title: String
        let message: String
        let time: String
    }

    /// What the app really sends, in its own words.
    private let samples = [
        Sample(title: "Morning briefing", message: "Green recovery. Full effort today.", time: "now"),
        Sample(title: "Streak at risk", message: "Log one thing before midnight.", time: "21:30"),
        Sample(title: "Training in 30 min", message: "Upper body. Don't skip it.", time: "17:30"),
    ]

    var body: some View {
        OnboardingScaffold(
            title: "THE DRILL SERGEANT\nNEEDS YOUR ATTENTION.",
            primaryTitle: "ENABLE NOTIFICATIONS",
            primaryAction: {
                Task {
                    let center = UNUserNotificationCenter.current()
                    let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
                    viewModel.notificationsGranted = granted ?? false
                    // Also request location here (powers the weather tips above).
                    // No-op if already determined; degrades silently if denied.
                    await locationAuthorizer.requestWhenInUseIfNeeded()
                    viewModel.advance()
                }
            },
            skipAction: { viewModel.skip() },
            centered: true
        ) {
            // Three banners land top to bottom, the way they would on the lock screen.
            VStack(spacing: Tide.s2) {
                HStack {
                    Text("On your lock screen").tideLabel()
                    Spacer(minLength: Tide.s2)
                    OnboardingSampleTag()
                }
                .padding(.bottom, Tide.s1)
                ForEach(Array(samples.enumerated()), id: \.element) { index, sample in
                    OnboardingBanner(title: sample.title, message: sample.message, time: sample.time)
                        .opacity(shown > index ? 1 : 0)
                        .offset(y: shown > index || reduceMotion ? 0 : -Tide.s4)
                        .scaleEffect(shown > index || reduceMotion ? 1 : 0.96)
                }
            }

            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingBenefitRow(systemImage: "sunrise.fill", text: "Morning briefings")
                OnboardingBenefitRow(systemImage: "clock.fill", text: "Accountability check-ins")
                OnboardingBenefitRow(systemImage: "flame.fill", text: "Streak protection alerts")
                OnboardingBenefitRow(systemImage: "trophy.fill", text: "Achievement celebrations")
                OnboardingBenefitRow(systemImage: "cloud.sun.fill", text: "Weather-aware hydration & training tips")
            }
            .onboardingCard()

            OnboardingNote("You control exactly what and when. Adjust anytime in Settings.")
        }
        .task {
            if reduceMotion {
                shown = samples.count
                return
            }
            for index in 1 ... samples.count {
                try? await Task.sleep(for: .milliseconds(index == 1 ? 500 : 420))
                withAnimation(Tide.lively) { shown = index }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: shown)
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

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    NotificationSetupView(viewModel: vm)
        .tidePage(energy: 1)
}
