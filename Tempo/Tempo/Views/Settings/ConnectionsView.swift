//
// ConnectionsView.swift
// Tempo
//
// One page for everything Tempo connects to: Whoop, Apple Health, Calendar and
// location (for the weather tips). Each has its status and one button. The
// Whoop button opens the Whoop page, which keeps its own sign-in and
// disconnect; the others show the system prompt, or take the user to iOS
// Settings once they have answered it.
//

import CoreLocation
import EventKit
import HealthKit
import SwiftUI
import UIKit

// MARK: - ConnectionsSnapshot

/// Reads the live state of each connection and hands it to the pure resolvers.
@MainActor
enum ConnectionsSnapshot {
    static func calendarAccess() -> SystemAccess {
        SystemAccess(EKEventStore.authorizationStatus(for: .event))
    }

    static func locationAccess() -> SystemAccess {
        SystemAccess(CLLocationManager().authorizationStatus)
    }

    /// True when Health is on but every type Tempo writes is switched off.
    static func healthWriteDenied() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }
        let store = HKHealthStore()
        return HealthKitConstants.writeTypes.allSatisfy { store.authorizationStatus(for: $0) == .sharingDenied }
    }

    static func lastSyncText(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    /// The four statuses, in page order.
    static func statuses(
        whoop: any WhoopServiceProtocol,
        healthAsked: Bool,
        calendar: SystemAccess = calendarAccess(),
        location: SystemAccess = locationAccess()
    ) -> [ConnectionStatus] {
        [
            .whoop(
                state: whoop.connectionState, isDemo: whoop.isDemoMode,
                hasCredentials: whoop.hasCredentials, lastSyncText: lastSyncText(whoop.lastSyncDate)
            ),
            .health(
                isAvailable: HKHealthStore.isHealthDataAvailable(),
                hasAsked: healthAsked, writeDenied: healthWriteDenied()
            ),
            .calendar(calendar),
            .location(location),
        ]
    }
}

// MARK: - ConnectionsView

struct ConnectionsView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.scenePhase)
    private var scenePhase

    /// Set once Tempo has shown the Health sheet (the same flag Today reads).
    @AppStorage("healthKitAuthorized")
    private var healthAsked = false

    @State
    private var calendarAccess = ConnectionsSnapshot.calendarAccess()
    @State
    private var locationAccess = ConnectionsSnapshot.locationAccess()
    @State
    private var busy: ConnectionKind?
    @State
    private var errors: [ConnectionKind: String] = [:]
    @State
    private var showWhoop = false
    /// Held for the life of the page so the location prompt can answer.
    @State
    private var locationAuthorizer = LocationAuthorizer()

    private var statuses: [ConnectionStatus] {
        ConnectionsSnapshot.statuses(
            whoop: services.whoop, healthAsked: healthAsked,
            calendar: calendarAccess, location: locationAccess
        )
    }

    var body: some View {
        TideSettingsPage {
            let all = statuses
            summaryLine(all)

            ForEach(all) { status in
                SettingsConnectionCard(
                    icon: status.kind.icon,
                    title: status.kind.title,
                    statusText: status.statusText,
                    statusColor: color(for: status.tone),
                    detail: status.detail,
                    buttonTitle: status.buttonTitle,
                    isBusy: busy == status.kind,
                    errorText: errors[status.kind],
                    identifier: "connectionButton-\(status.kind.rawValue)"
                ) {
                    perform(status)
                }
                .accessibilityIdentifier("connectionCard-\(status.kind.rawValue)")
            }

            Text("Tempo only reads what it needs. You can turn any of these off at any time.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tide.s2)
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showWhoop) {
            WhoopConnectionView()
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings: read what the user chose there.
            if phase == .active {
                refresh()
            }
        }
    }

    // MARK: Pieces

    private func summaryLine(_ all: [ConnectionStatus]) -> some View {
        Text(ConnectionStatus.summary(all))
            .font(Tide.title2)
            .foregroundStyle(Tide.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tide.s2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("connectionsSummary")
    }

    private func color(for tone: ConnectionTone) -> Color {
        switch tone {
        case .ok: Tide.settingsOK
        case .off: Tide.text3
        case .attention: Tide.settingsAttention
        }
    }

    // MARK: Actions

    private func refresh() {
        calendarAccess = ConnectionsSnapshot.calendarAccess()
        locationAccess = ConnectionsSnapshot.locationAccess()
    }

    private func perform(_ status: ConnectionStatus) {
        errors[status.kind] = nil
        switch status.action {
        case .openWhoop:
            showWhoop = true
        case .openSystemSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .askPermission:
            Task { await ask(status.kind) }
        }
    }

    @MainActor
    private func ask(_ kind: ConnectionKind) async {
        guard busy == nil else {
            return
        }
        busy = kind
        defer {
            busy = nil
            refresh()
        }
        do {
            switch kind {
            case .health:
                try await services.healthKit.requestAuthorization()
            case .calendar:
                try await services.calendar.requestAuthorization()
            case .location:
                await locationAuthorizer.requestWhenInUseIfNeeded()
            case .whoop:
                break
            }
        } catch {
            errors[kind] = "Couldn't ask for access. Try again, or open Settings."
        }
    }
}
