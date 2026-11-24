//
// PermissionsSetupView.swift
// Tempo
//
// The one permissions step: Apple Health, notifications and location, each with its own
// button. All optional, and each can be turned on later in Settings > Connections or
// Settings > Notifications.
//

import HealthKit
import SwiftUI
import UserNotifications

// MARK: - PermissionsSetupView

struct PermissionsSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.scenePhase)
    private var scenePhase

    /// Set once Tempo has shown the Health sheet (the same flag Today reads).
    @AppStorage("healthKitAuthorized")
    private var healthAsked = false

    @State
    private var notifications: SystemAccess = .notAsked
    @State
    private var location: SystemAccess = ConnectionsSnapshot.locationAccess()
    @State
    private var busy: Kind?
    @State
    private var errors: [Kind: String] = [:]
    /// Held for the life of the page so the location prompt can answer.
    @State
    private var locationAuthorizer = LocationAuthorizer()

    enum Kind: String, CaseIterable, Identifiable {
        case health
        case notifications
        case location

        var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .health: "heart.fill"
            case .notifications: "bell.badge.fill"
            case .location: "location.fill"
            }
        }

        var title: String {
            switch self {
            case .health: "Apple Health"
            case .notifications: "Notifications"
            case .location: "Location"
            }
        }

        var why: String {
            switch self {
            case .health: "Steps, sleep and workouts, so your day starts with real numbers."
            case .notifications: "Morning briefings, meal and training reminders, streak alerts."
            case .location: "Weather tips, run pace and distance, and meals eaten out."
            }
        }
    }

    var body: some View {
        OnboardingScaffold(
            title: "WHAT CAN\nTEMPO USE?",
            subtitle: "All optional. You can change any of them later in Settings.",
            primaryTitle: "CONTINUE",
            primaryAction: { viewModel.advance() }
        ) {
            VStack(spacing: Tide.s3) {
                ForEach(Kind.allCases) { kind in
                    PermissionRow(
                        icon: kind.icon,
                        title: kind.title,
                        why: kind.why,
                        access: access(for: kind),
                        grantedText: kind == .health ? "Done" : "On",
                        isBusy: busy == kind,
                        errorText: errors[kind],
                        identifier: kind.rawValue
                    ) {
                        act(on: kind)
                    }
                }
            }

            OnboardingNote(
                "Your health data stays on your device. Tempo never uploads raw HealthKit data.",
                systemImage: "lock.fill"
            )
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
    }

    // MARK: - State

    private func access(for kind: Kind) -> SystemAccess {
        switch kind {
        case .health:
            if !HKHealthStore.isHealthDataAvailable() {
                return .unavailable
            }
            // Health never says whether reading was allowed: "asked" is as much as an app can know.
            return healthAsked ? .granted : .notAsked
        case .notifications:
            return notifications
        case .location:
            return location
        }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = switch settings.authorizationStatus {
        case .authorized,
             .provisional,
             .ephemeral: .granted
        case .denied: .denied
        case .notDetermined: .notAsked
        @unknown default: .notAsked
        }
        location = ConnectionsSnapshot.locationAccess()
    }

    // MARK: - Actions

    private func act(on kind: Kind) {
        switch access(for: kind) {
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .notAsked:
            Task { await ask(kind) }
        default:
            break
        }
    }

    private func ask(_ kind: Kind) async {
        guard busy == nil else {
            return
        }
        busy = kind
        errors[kind] = nil
        defer { busy = nil }
        do {
            switch kind {
            case .health:
                try await services.healthKit.requestAuthorization()
                viewModel.healthkitGranted = true
            case .notifications:
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                viewModel.notificationsGranted = granted
            case .location:
                await locationAuthorizer.requestWhenInUseIfNeeded()
            }
        } catch {
            errors[kind] = "Couldn't ask for access. Try again, or turn it on in Settings later."
        }
        await refresh()
    }
}

// MARK: - PermissionRow

/// One permission: a symbol, what it is for, and one button that says where it stands.
private struct PermissionRow: View {
    let icon: String
    let title: String
    let why: String
    let access: SystemAccess
    /// Health never says whether reading was allowed, so its row says "Done", not "On".
    let grantedText: String
    let isBusy: Bool
    let errorText: String?
    let identifier: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s3))
            layout {
                HStack(alignment: .top, spacing: Tide.s3) {
                    TideIconTile(systemName: icon)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(title)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(why)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s2)
                    }
                }
                trailing
            }
            if let errorText {
                Text(errorText)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onboardingCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permissionRow-\(identifier)")
    }

    @ViewBuilder
    private var trailing: some View {
        if isBusy {
            ProgressView()
                .tint(Tide.text)
                .frame(minWidth: Tide.hit, minHeight: Tide.hit)
        } else {
            switch access {
            case .granted,
                 .limited:
                Label(grantedText, systemImage: "checkmark.circle.fill")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.good)
                    .frame(minHeight: Tide.hit)
                    .accessibilityIdentifier("permissionState-\(identifier)")
            case .notAsked:
                Button("Allow", action: action)
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("permissionAllow-\(identifier)")
            case .denied:
                Button("Open Settings", action: action)
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("permissionOpenSettings-\(identifier)")
            case .restricted,
                 .unavailable:
                Text("Not available")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .frame(minHeight: Tide.hit)
            }
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    PermissionsSetupView(viewModel: vm)
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
