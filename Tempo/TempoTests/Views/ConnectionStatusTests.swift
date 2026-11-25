//
// ConnectionStatusTests.swift
// Tempo
//
// The Connections page shows each service with a status and one button.
// These pin down what each situation says and does.
//

import CoreLocation
import EventKit
@testable import Tempo
import XCTest

final class ConnectionStatusTests: XCTestCase {
    // MARK: - Whoop

    func testWhoop_connectedRealAccount_isOkAndOpensWhoop() {
        let status = ConnectionStatus.whoop(
            state: .connected, isDemo: false, hasCredentials: true, lastSyncText: "5 min. ago"
        )
        XCTAssertEqual(status.tone, .ok)
        XCTAssertEqual(status.statusText, "Connected")
        XCTAssertEqual(status.action, .openWhoop)
        XCTAssertEqual(status.buttonTitle, "Manage")
        XCTAssertTrue(status.detail.contains("5 min. ago"))
        XCTAssertTrue(status.isConnected)
    }

    func testWhoop_demoData_isNeverShownAsConnected() {
        let status = ConnectionStatus.whoop(state: .connected, isDemo: true, hasCredentials: true)
        XCTAssertEqual(status.tone, .attention)
        XCTAssertEqual(status.statusText, "Demo data")
        XCTAssertFalse(status.isConnected)
    }

    func testWhoop_disconnected_withoutKeys_saysWhatItNeeds() {
        let withKeys = ConnectionStatus.whoop(state: .disconnected, isDemo: false, hasCredentials: true)
        let noKeys = ConnectionStatus.whoop(state: .disconnected, isDemo: false, hasCredentials: false)
        XCTAssertEqual(withKeys.buttonTitle, "Connect")
        XCTAssertEqual(withKeys.tone, .off)
        XCTAssertFalse(withKeys.detail.contains("developer keys"))
        XCTAssertTrue(noKeys.detail.contains("developer keys"))
    }

    func testWhoop_error_showsTheReasonAndAFix() {
        let status = ConnectionStatus.whoop(state: .error("Token expired"), isDemo: false, hasCredentials: true)
        XCTAssertEqual(status.tone, .attention)
        XCTAssertEqual(status.detail, "Token expired")
        XCTAssertEqual(status.buttonTitle, "Fix connection")
        let blank = ConnectionStatus.whoop(state: .error(""), isDemo: false, hasCredentials: true)
        XCTAssertFalse(blank.detail.isEmpty)
    }

    func testWhoop_connecting_isNotOnYet() {
        let status = ConnectionStatus.whoop(state: .connecting, isDemo: false, hasCredentials: true)
        XCTAssertEqual(status.tone, .off)
        XCTAssertFalse(status.isConnected)
    }

    // MARK: - Apple Health

    func testHealth_unavailable_offersOnlySettings() {
        let status = ConnectionStatus.health(isAvailable: false, hasAsked: true, writeDenied: false)
        XCTAssertEqual(status.statusText, "Not available")
        XCTAssertEqual(status.action, .openSystemSettings)
    }

    func testHealth_neverAsked_asksForPermission() {
        let status = ConnectionStatus.health(isAvailable: true, hasAsked: false, writeDenied: false)
        XCTAssertEqual(status.action, .askPermission)
        XCTAssertEqual(status.buttonTitle, "Connect")
        XCTAssertEqual(status.tone, .off)
    }

    func testHealth_asked_isConnected() {
        let status = ConnectionStatus.health(isAvailable: true, hasAsked: true, writeDenied: false)
        XCTAssertEqual(status.tone, .ok)
        XCTAssertEqual(status.action, .openSystemSettings)
    }

    func testHealth_writesSwitchedOff_needsAttention() {
        let status = ConnectionStatus.health(isAvailable: true, hasAsked: true, writeDenied: true)
        XCTAssertEqual(status.tone, .attention)
        XCTAssertFalse(status.isConnected)
    }

    // MARK: - Calendar and location

    func testCalendar_everyAccessLevelHasOneButton() {
        let expected: [SystemAccess: (ConnectionTone, ConnectionAction)] = [
            .notAsked: (.off, .askPermission),
            .granted: (.ok, .openSystemSettings),
            .limited: (.attention, .openSystemSettings),
            .denied: (.attention, .openSystemSettings),
            .restricted: (.attention, .openSystemSettings),
            .unavailable: (.off, .openSystemSettings),
        ]
        for (access, want) in expected {
            let status = ConnectionStatus.calendar(access)
            XCTAssertEqual(status.tone, want.0, "\(access)")
            XCTAssertEqual(status.action, want.1, "\(access)")
            XCTAssertFalse(status.buttonTitle.isEmpty)
            XCTAssertFalse(status.detail.isEmpty)
        }
    }

    func testCalendar_addOnlyAccessIsNotConnected() {
        XCTAssertFalse(ConnectionStatus.calendar(.limited).isConnected)
    }

    func testLocation_notAsked_allowsInApp_deniedGoesToSettings() {
        XCTAssertEqual(ConnectionStatus.location(.notAsked).action, .askPermission)
        XCTAssertEqual(ConnectionStatus.location(.notAsked).buttonTitle, "Allow")
        XCTAssertEqual(ConnectionStatus.location(.denied).action, .openSystemSettings)
        XCTAssertEqual(ConnectionStatus.location(.granted).tone, .ok)
    }

    // MARK: - System status mapping

    func testSystemAccess_mapsCalendarStatuses() {
        XCTAssertEqual(SystemAccess(EKAuthorizationStatus.fullAccess), .granted)
        XCTAssertEqual(SystemAccess(EKAuthorizationStatus.writeOnly), .limited)
        XCTAssertEqual(SystemAccess(EKAuthorizationStatus.denied), .denied)
        XCTAssertEqual(SystemAccess(EKAuthorizationStatus.restricted), .restricted)
        XCTAssertEqual(SystemAccess(EKAuthorizationStatus.notDetermined), .notAsked)
    }

    func testSystemAccess_mapsLocationStatuses() {
        XCTAssertEqual(SystemAccess(CLAuthorizationStatus.authorizedWhenInUse), .granted)
        XCTAssertEqual(SystemAccess(CLAuthorizationStatus.authorizedAlways), .granted)
        XCTAssertEqual(SystemAccess(CLAuthorizationStatus.denied), .denied)
        XCTAssertEqual(SystemAccess(CLAuthorizationStatus.restricted), .restricted)
        XCTAssertEqual(SystemAccess(CLAuthorizationStatus.notDetermined), .notAsked)
    }

    // MARK: - Summary

    private func status(_ kind: ConnectionKind, _ tone: ConnectionTone) -> ConnectionStatus {
        ConnectionStatus(
            kind: kind, statusText: "x", tone: tone, detail: "d", buttonTitle: "b", action: .openSystemSettings
        )
    }

    func testSummary_countsAndPrioritisesAttention() {
        let none = ConnectionKind.allCases.map { status($0, .off) }
        XCTAssertEqual(ConnectionStatus.summary(none), "Nothing connected yet")
        XCTAssertEqual(ConnectionStatus.summaryTone(none), .off)

        var some = none
        some[0] = status(.whoop, .ok)
        some[1] = status(.health, .ok)
        XCTAssertEqual(ConnectionStatus.summary(some), "2 of 4 connected")

        let all = ConnectionKind.allCases.map { status($0, .ok) }
        XCTAssertEqual(ConnectionStatus.summary(all), "All connected")
        XCTAssertEqual(ConnectionStatus.summaryTone(all), .ok)

        var one = all
        one[2] = status(.calendar, .attention)
        XCTAssertEqual(ConnectionStatus.summary(one), "1 needs attention")
        XCTAssertEqual(ConnectionStatus.summaryTone(one), .attention)
        one[3] = status(.location, .attention)
        XCTAssertEqual(ConnectionStatus.summary(one), "2 need attention")
    }

    func testSummary_emptyListIsNotGreen() {
        XCTAssertEqual(ConnectionStatus.summaryTone([]), .off)
    }
}
