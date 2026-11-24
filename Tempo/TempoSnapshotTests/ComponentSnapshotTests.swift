//
// ComponentSnapshotTests.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SnapshotTesting
import SwiftUI
@testable import Tempo
import XCTest

// MARK: - Component Snapshot Tests

// Per BUILD_PLAN Step 19.4 — Snapshot tests for shared components.

final class ComponentSnapshotTests: TempoSnapshotTestCase {
    // MARK: - Empty State

    func testEmptyStateView() {
        let view = EmptyStateView(
            icon: "tray",
            title: "No Data Yet",
            message: "Start tracking to see your progress here."
        )
        assertComponentSnapshot(of: view, size: CGSize(width: 393, height: 300))
    }

    // MARK: - Loading State

    func testLoadingStateView() {
        let view = LoadingStateView()
        assertComponentSnapshot(of: view, size: CGSize(width: 393, height: 300))
    }

    // MARK: - Error State

    func testErrorStateView() {
        let view = ErrorStateView(
            title: "Something went wrong",
            message: "Check your connection and try again.",
            retryAction: {}
        )
        assertComponentSnapshot(of: view, size: CGSize(width: 393, height: 300))
    }

    // MARK: - Settings Toolbar Icon

    // Phase 2 — canonical settings gear icon used by all 5 tab roots.

    func testSettingsToolbarIcon() {
        let view = Image(systemName: TempoSymbols.settings)
            .font(.tempoBody)
            .foregroundStyle(Color.tempoTextSecondary)
            .frame(width: 44, height: 44, alignment: .trailing)
        assertComponentSnapshot(of: view, size: CGSize(width: 44, height: 44))
    }

    // MARK: - Body Quadrant Metric Cards (Bug #3 regression)

    /// Pins HRV/RHR/Sleep/SpO2 cards at identical dimensions. If a future change
    /// re-introduces unit suffixes inside the value or removes the minHeight,
    /// this snapshot will fail.
    func testBodyQuadrantDetailMetricRow() {
        let view = NavigationStack {
            BodyQuadrantDetailView(
                data: BodyQuadrantData(
                    recoveryScore: 72, hrv: 48, rhr: 62, sleepHours: 7.2,
                    sleepPerformance: 78, strain: 12.4, spo2: 97.5,
                    isConnected: true, lastSync: Date(),
                    dataSource: .whoop
                )
            )
        }
        assertComponentSnapshot(of: view, size: CGSize(width: 393, height: 360))
    }
}
