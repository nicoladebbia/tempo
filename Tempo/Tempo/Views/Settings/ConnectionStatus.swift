//
// ConnectionStatus.swift
// Tempo
//
// What the Connections page says about each outside service, worked out in one
// place from plain inputs, so every card shows a status, a line about it and
// exactly one button, and the wording can be tested without a device.
//

import CoreLocation
import EventKit
import Foundation

// MARK: - ConnectionKind

enum ConnectionKind: String, CaseIterable, Identifiable, Sendable {
    case whoop
    case health
    case calendar
    case location

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .whoop: "Whoop"
        case .health: "Apple Health"
        case .calendar: "Calendar"
        case .location: "Weather (location)"
        }
    }

    var icon: String {
        switch self {
        case .whoop: "waveform.path.ecg"
        case .health: "heart.text.square.fill"
        case .calendar: "calendar"
        case .location: "cloud.sun.fill"
        }
    }

    /// What the connection is for, in one line, shown while it is off.
    var purpose: String {
        switch self {
        case .whoop: "Recovery, sleep and strain from your band."
        case .health: "Steps, heart rate and sleep in; your workouts and meals out."
        case .calendar: "Plans training and meals around your day."
        case .location: "Weather-aware training and hydration tips."
        }
    }
}

// MARK: - SystemAccess

/// A system permission, reduced to what the page needs to tell apart.
enum SystemAccess: Equatable, Sendable {
    case notAsked
    case granted
    /// Calendar only: Tempo may add events but not read them.
    case limited
    case denied
    /// A parental or device policy blocks it; the user cannot change it.
    case restricted
    case unavailable

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .fullAccess: self = .granted
        case .writeOnly: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notAsked
        @unknown default: self = .notAsked
        }
    }

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways,
             .authorizedWhenInUse: self = .granted
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notAsked
        @unknown default: self = .notAsked
        }
    }
}

// MARK: - ConnectionTone

enum ConnectionTone: Equatable, Sendable {
    /// On and working.
    case ok
    /// Off, and nothing is wrong.
    case off
    /// Needs the user to do something.
    case attention
}

// MARK: - ConnectionAction

/// The one thing a card's button does.
enum ConnectionAction: Equatable, Sendable {
    /// Push the Whoop page (credentials, connect, disconnect, data preview).
    case openWhoop
    /// Show the system permission prompt, then re-read the status.
    case askPermission
    /// Take the user to Tempo's page in the iOS Settings app.
    case openSystemSettings
}

// MARK: - ConnectionStatus

struct ConnectionStatus: Equatable, Identifiable, Sendable {
    let kind: ConnectionKind
    /// The pill: "Connected", "Not connected", "Needs attention".
    let statusText: String
    let tone: ConnectionTone
    /// One line under the title: what it gives, or what to do.
    let detail: String
    let buttonTitle: String
    let action: ConnectionAction

    var id: String {
        kind.rawValue
    }

    var isConnected: Bool {
        tone == .ok
    }
}

// MARK: - Resolvers

extension ConnectionStatus {
    /// Whoop: its own connection state, plus whether this is demo data.
    static func whoop(
        state: WhoopConnectionState,
        isDemo: Bool,
        hasCredentials: Bool,
        lastSyncText: String? = nil
    ) -> ConnectionStatus {
        let kind = ConnectionKind.whoop
        switch state {
        case .connected:
            if isDemo {
                return ConnectionStatus(
                    kind: kind, statusText: "Demo data", tone: .attention,
                    detail: "These numbers are samples, not yours. Connect your own band to see real ones.",
                    buttonTitle: "Connect Whoop", action: .openWhoop
                )
            }
            return ConnectionStatus(
                kind: kind, statusText: "Connected", tone: .ok,
                detail: lastSyncText.map { "Last synced \($0)." } ?? "Recovery, sleep and strain are flowing in.",
                buttonTitle: "Manage", action: .openWhoop
            )
        case .connecting:
            return ConnectionStatus(
                kind: kind, statusText: "Connecting", tone: .off,
                detail: "Finish signing in with Whoop.",
                buttonTitle: "Open", action: .openWhoop
            )
        case let .error(message):
            return ConnectionStatus(
                kind: kind, statusText: "Needs attention", tone: .attention,
                detail: message.isEmpty ? "Whoop stopped answering. Reconnect to bring your data back." : message,
                buttonTitle: "Fix connection", action: .openWhoop
            )
        case .disconnected:
            return ConnectionStatus(
                kind: kind, statusText: "Not connected", tone: .off,
                detail: hasCredentials ? kind.purpose : "\(kind.purpose) Needs your Whoop developer keys.",
                buttonTitle: "Connect", action: .openWhoop
            )
        }
    }

    /// Apple Health. Health never tells an app whether it may read, so the
    /// page goes by what Tempo asked for and whether it may write.
    /// - Parameters:
    ///   - isAvailable: false on iPad and other devices without Health.
    ///   - hasAsked: Tempo has shown the Health sheet at least once.
    ///   - writeDenied: every type Tempo writes is switched off in Health.
    static func health(isAvailable: Bool, hasAsked: Bool, writeDenied: Bool) -> ConnectionStatus {
        let kind = ConnectionKind.health
        guard isAvailable else {
            return ConnectionStatus(
                kind: kind, statusText: "Not available", tone: .off,
                detail: "Apple Health isn't available on this device.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        }
        guard hasAsked else {
            return ConnectionStatus(
                kind: kind, statusText: "Not connected", tone: .off,
                detail: kind.purpose,
                buttonTitle: "Connect", action: .askPermission
            )
        }
        if writeDenied {
            return ConnectionStatus(
                kind: kind, statusText: "Needs attention", tone: .attention,
                detail: "Tempo can't save workouts or meals to Health. Turn them on in Health settings.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        }
        return ConnectionStatus(
            kind: kind, statusText: "Connected", tone: .ok,
            detail: "Steps, heart rate and sleep come in; workouts and meals go back out.",
            buttonTitle: "Manage in Settings", action: .openSystemSettings
        )
    }

    /// Calendar.
    static func calendar(_ access: SystemAccess) -> ConnectionStatus {
        let kind = ConnectionKind.calendar
        switch access {
        case .granted:
            return ConnectionStatus(
                kind: kind, statusText: "Connected", tone: .ok,
                detail: "Tempo plans training and meals around your events.",
                buttonTitle: "Manage in Settings", action: .openSystemSettings
            )
        case .limited:
            return ConnectionStatus(
                kind: kind, statusText: "Needs attention", tone: .attention,
                detail: "Tempo can add events but can't read them. Allow full access to plan around your day.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        case .denied:
            return ConnectionStatus(
                kind: kind, statusText: "Turned off", tone: .attention,
                detail: "Calendar access is off, so plans ignore your events. Turn it on in Settings.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        case .restricted:
            return ConnectionStatus(
                kind: kind, statusText: "Blocked", tone: .attention,
                detail: "This device doesn't let apps use the calendar.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        case .unavailable:
            return ConnectionStatus(
                kind: kind, statusText: "Not available", tone: .off,
                detail: "The calendar isn't available on this device.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        case .notAsked:
            return ConnectionStatus(
                kind: kind, statusText: "Not connected", tone: .off,
                detail: kind.purpose,
                buttonTitle: "Connect", action: .askPermission
            )
        }
    }

    /// Location, for the weather tips.
    static func location(_ access: SystemAccess) -> ConnectionStatus {
        let kind = ConnectionKind.location
        switch access {
        case .granted:
            return ConnectionStatus(
                kind: kind, statusText: "Allowed", tone: .ok,
                detail: "Training and hydration tips follow your local weather.",
                buttonTitle: "Manage in Settings", action: .openSystemSettings
            )
        case .denied,
             .limited:
            return ConnectionStatus(
                kind: kind, statusText: "Turned off", tone: .attention,
                detail: "Without location, weather tips are skipped. Turn it on in Settings.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        case .restricted:
            return ConnectionStatus(
                kind: kind, statusText: "Blocked", tone: .attention,
                detail: "This device doesn't let apps use your location.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        case .unavailable:
            return ConnectionStatus(
                kind: kind, statusText: "Not available", tone: .off,
                detail: "Location isn't available on this device.",
                buttonTitle: "Open Settings", action: .openSystemSettings
            )
        case .notAsked:
            return ConnectionStatus(
                kind: kind, statusText: "Not allowed", tone: .off,
                detail: kind.purpose,
                buttonTitle: "Allow", action: .askPermission
            )
        }
    }
}

// MARK: - Summary

extension ConnectionStatus {
    /// The line under "Connections" on the Settings page: how many are on, and
    /// a nudge when one needs the user.
    static func summary(_ statuses: [ConnectionStatus]) -> String {
        let needing = statuses.filter { $0.tone == .attention }.count
        if needing > 0 {
            return needing == 1 ? "1 needs attention" : "\(needing) need attention"
        }
        let on = statuses.filter(\.isConnected).count
        if on == 0 {
            return "Nothing connected yet"
        }
        return on == statuses.count ? "All connected" : "\(on) of \(statuses.count) connected"
    }

    /// The colour of the summary: amber when something needs the user, green
    /// when everything is on, grey otherwise.
    static func summaryTone(_ statuses: [ConnectionStatus]) -> ConnectionTone {
        if statuses.contains(where: { $0.tone == .attention }) {
            return .attention
        }
        return !statuses.isEmpty && statuses.allSatisfy(\.isConnected) ? .ok : .off
    }
}
