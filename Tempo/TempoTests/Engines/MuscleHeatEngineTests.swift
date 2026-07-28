//
// MuscleHeatEngineTests.swift
// Tempo
//
// §11.5 — pins the heatmap math: secondary movers at half credit, window
// boundaries, normalization by the hottest muscle, unmappable rows
// (fullBody/cardio) excluded, and delta's explicit-nil for muscles with no
// prior-week baseline.
//

@testable import Tempo
import XCTest

final class MuscleHeatEngineTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private var now: Date { Date(timeIntervalSince1970: 1_753_700_000) }

    private func row(
        _ primary: MuscleGroup,
        secondaries: [MuscleGroup] = [],
        volume: Double,
        sets: Int = 3,
        daysAgo: Double
    ) -> MuscleHeatEngine.ContributionRow {
        MuscleHeatEngine.ContributionRow(
            primary: primary, secondaries: secondaries, volume: volume,
            sets: sets, date: now.addingTimeInterval(-daysAgo * day)
        )
    }

    func testPrimaryFullCreditSecondariesHalf() {
        let rows = [row(.chest, secondaries: [.triceps, .shoulders], volume: 1000, daysAgo: 1)]
        let volumes = MuscleHeatEngine.volumes(
            rows: rows, from: now.addingTimeInterval(-7 * day), to: now
        )
        XCTAssertEqual(volumes[.chest], 1000)
        XCTAssertEqual(volumes[.triceps], 500)
        XCTAssertEqual(volumes[.shoulders], 500)
    }

    func testWindowBoundariesExcludeOutsideRows() {
        let rows = [
            row(.quads, volume: 800, daysAgo: 1),
            row(.quads, volume: 999, daysAgo: 8), // previous week
        ]
        let volumes = MuscleHeatEngine.volumes(
            rows: rows, from: now.addingTimeInterval(-7 * day), to: now
        )
        XCTAssertEqual(volumes[.quads], 800, "Only in-window rows heat the map")
    }

    func testUnmappableMusclesExcluded() {
        let rows = [row(.fullBody, secondaries: [.cardio], volume: 500, daysAgo: 1)]
        let volumes = MuscleHeatEngine.volumes(
            rows: rows, from: now.addingTimeInterval(-7 * day), to: now
        )
        XCTAssertTrue(volumes.isEmpty, "fullBody/cardio have no body location — never smeared")
    }

    func testHeatNormalizesByPeak() {
        let heat = MuscleHeatEngine.heat([.chest: 1000, .biceps: 250])
        XCTAssertEqual(heat[.chest], 1.0)
        XCTAssertEqual(heat[.biceps], 0.25)
        XCTAssertTrue(MuscleHeatEngine.heat([:]).isEmpty)
    }

    func testDeltaSignedAndExplicitNilWithoutBaseline() {
        let deltas = MuscleHeatEngine.delta(
            current: [.chest: 1200, .quads: 400, .calves: 300],
            previous: [.chest: 1000, .quads: 800]
        )
        XCTAssertEqual(deltas[.chest] ?? nil, 0.2, "+20% week over week")
        XCTAssertEqual(deltas[.quads] ?? nil, -0.5)
        XCTAssertNotNil(deltas.index(forKey: .calves), "Key present…")
        XCTAssertNil(deltas[.calves] ?? nil, "…but explicitly no-baseline")
    }

    func testSetCountsPrimaryOnly() {
        let rows = [
            row(.chest, secondaries: [.triceps], volume: 1000, sets: 4, daysAgo: 1),
            row(.chest, volume: 500, sets: 3, daysAgo: 2),
        ]
        let counts = MuscleHeatEngine.setCounts(
            rows: rows, from: now.addingTimeInterval(-7 * day), to: now
        )
        XCTAssertEqual(counts[.chest], 7)
        XCTAssertNil(counts[.triceps], "A set belongs to its primary muscle only")
    }
}
