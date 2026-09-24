//
// WidgetSyncServiceTests.swift
// Tempo
//
// The widget read `widget.*` keys from the app group that nothing wrote,
// so it always showed zeros. These pin the writer: every key the widget's
// `WidgetData.fromDefaults()` reads is written with the snapshot value,
// timelines reload on change, and an unchanged snapshot doesn't re-reload.
//

@testable import Tempo
import XCTest

@MainActor
final class WidgetSyncServiceTests: XCTestCase {
    private let suiteName = "WidgetSyncServiceTests"
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
        WidgetSyncService.resetDedupe()
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        WidgetSyncService.resetDedupe()
        defaults = nil
        try await super.tearDown()
    }

    private var sample: WidgetSnapshot {
        WidgetSnapshot(
            dailyScore: 81, recoveryZone: "yellow", recoveryScore: 55,
            sleepHours: 7.4, hrv: 62.5, rhr: 51,
            caloriesConsumed: 1840, caloriesTarget: 2600,
            protein: 150, carbs: 190, fat: 60,
            mealsLogged: 3, mealsTarget: 5,
            studyMinutes: 95, studyTargetMinutes: 120, streakCount: 9,
            nextExam: "Calculus: in 4 days", workoutDone: true,
            stepCount: 9100, activeCalories: 480,
            nnCompleted: 2, nnTotal: 4
        )
    }

    /// Keys exactly as `TempoWidget/TempoWidget.swift` → `fromDefaults()` reads them.
    func testWritesEveryKeyTheWidgetReads() {
        WidgetSyncService.write(sample, to: defaults)

        XCTAssertEqual(defaults.integer(forKey: "widget.dailyScore"), 81)
        XCTAssertEqual(defaults.string(forKey: "widget.recoveryZone"), "yellow")
        XCTAssertEqual(defaults.integer(forKey: "widget.recoveryScore"), 55)
        XCTAssertEqual(defaults.double(forKey: "widget.sleepHours"), 7.4)
        XCTAssertEqual(defaults.double(forKey: "widget.hrv"), 62.5)
        XCTAssertEqual(defaults.integer(forKey: "widget.rhr"), 51)
        XCTAssertEqual(defaults.integer(forKey: "widget.caloriesConsumed"), 1840)
        XCTAssertEqual(defaults.integer(forKey: "widget.caloriesTarget"), 2600)
        XCTAssertEqual(defaults.integer(forKey: "widget.protein"), 150)
        XCTAssertEqual(defaults.integer(forKey: "widget.carbs"), 190)
        XCTAssertEqual(defaults.integer(forKey: "widget.fat"), 60)
        XCTAssertEqual(defaults.integer(forKey: "widget.mealsLogged"), 3)
        XCTAssertEqual(defaults.integer(forKey: "widget.mealsTarget"), 5)
        XCTAssertEqual(defaults.integer(forKey: "widget.studyMinutes"), 95)
        XCTAssertEqual(defaults.integer(forKey: "widget.studyTargetMinutes"), 120)
        XCTAssertEqual(defaults.integer(forKey: "widget.streakCount"), 9)
        XCTAssertEqual(defaults.string(forKey: "widget.nextExam"), "Calculus: in 4 days")
        XCTAssertTrue(defaults.bool(forKey: "widget.workoutDone"))
        XCTAssertEqual(defaults.integer(forKey: "widget.stepCount"), 9100)
        XCTAssertEqual(defaults.integer(forKey: "widget.activeCalories"), 480)
        XCTAssertEqual(defaults.integer(forKey: "widget.nnCompleted"), 2)
        XCTAssertEqual(defaults.integer(forKey: "widget.nnTotal"), 4)
    }

    func testPublishReloadsOnlyWhenSnapshotChanges() {
        var reloads = 0
        WidgetSyncService.publish(sample, defaults: defaults) { reloads += 1 }
        WidgetSyncService.publish(sample, defaults: defaults) { reloads += 1 }
        XCTAssertEqual(reloads, 1, "Identical snapshot must not re-reload timelines")

        var changed = sample
        changed.caloriesConsumed = 2300
        WidgetSyncService.publish(changed, defaults: defaults) { reloads += 1 }
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(defaults.integer(forKey: "widget.caloriesConsumed"), 2300)
    }

    func testPublishWithoutAppGroupIsNoOp() {
        var reloads = 0
        WidgetSyncService.publish(sample, defaults: nil) { reloads += 1 }
        XCTAssertEqual(reloads, 0)
    }
}
