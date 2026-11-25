//
// WidgetSyncServiceTests.swift
// Tempo
//
// The widgets draw one `WidgetSnapshot` the app writes into the app group.
// These pin the writer and the snapshot rules: the numbers are the Today
// screen's own, the next-up line is the same choice as the Today hero, an
// earlier day's progress never passes as today's, water logged with no screen
// patches only the water, and an unchanged refresh does not reload widgets.
//

@testable import Tempo
import XCTest

@MainActor
final class WidgetSyncServiceTests: XCTestCase {
    private let suiteName = "WidgetSyncServiceTests"
    private var defaults: UserDefaults!
    private var reloads = 0
    private let calendar = Calendar.current
    private lazy var today = calendar.startOfDay(for: Date())

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
        WidgetSyncService.resetDedupe()
        reloads = 0
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        WidgetSyncService.resetDedupe()
        defaults = nil
        try await super.tearDown()
    }

    private func todaySnapshot(
        workout: TodaySnapshot.Workout.Status = .planned,
        meal: TodaySnapshot.Meal? = nil,
        waterMl: Int = 750
    ) -> TodaySnapshot {
        TodaySnapshot(
            day: today,
            firstName: nil,
            score: 81,
            workout: .init(status: workout, name: "Push", inProgress: false, durationMinutes: 55),
            recovery: .init(score: 70, sleepHours: 7.4, sleepPerformance: 88, hrv: 62, restingHR: 51, hasSource: true),
            fuel: .init(
                calories: 1840, calorieTarget: 2600, protein: 150, proteinTarget: 190,
                carbs: 190, carbsTarget: 300, fat: 60, fatTarget: 80, waterMl: waterMl, waterTargetMl: 2900
            ),
            tasks: [
                .init(id: UUID(), title: "Read", done: true),
                .init(id: UUID(), title: "Stretch", done: false),
            ],
            study: .init(minutes: 0, targetMinutes: 0, nextExam: nil),
            streakDays: 9,
            steps: 9100,
            stepsTarget: 10000,
            moveConnected: true,
            nextMeal: meal
        )
    }

    private func publish(_ snapshot: WidgetSnapshot) {
        WidgetSyncService.publish(snapshot, defaults: defaults, reload: { [self] in reloads += 1 })
    }

    // MARK: Mapping from Today

    func testSnapshotCarriesTodaysNumbers() {
        let snap = WidgetSnapshot(today: todaySnapshot(), now: today.addingTimeInterval(9 * 3600))
        XCTAssertEqual(snap.score, 81)
        XCTAssertEqual(snap.calories, 1840)
        XCTAssertEqual(snap.calorieTarget, 2600)
        XCTAssertEqual(snap.protein, 150)
        XCTAssertEqual(snap.proteinTarget, 190)
        XCTAssertEqual(snap.carbs, 190)
        XCTAssertEqual(snap.fat, 60)
        XCTAssertEqual(snap.waterMl, 750)
        XCTAssertEqual(snap.waterTargetMl, 2900)
        XCTAssertEqual(snap.tasksDone, 1)
        XCTAssertEqual(snap.tasksTotal, 2)
        XCTAssertEqual(snap.day, today)
    }

    func testNextUpIsTheTodayHeroChoice() {
        let morning = today.addingTimeInterval(9 * 3600)
        let snap = WidgetSnapshot(today: todaySnapshot(), now: morning)
        XCTAssertEqual(snap.next?.kind, .workout)
        XCTAssertEqual(snap.next?.title, "Push")
        XCTAssertEqual(snap.next?.trailing, "55 min")
        XCTAssertEqual(snap.next?.destination, .train)

        let meal = TodaySnapshot.Meal(
            id: UUID(), name: "Lunch bowl", time: "12:30", calories: 780, protein: 62, imminent: true
        )
        let late = WidgetSnapshot(today: todaySnapshot(workout: .rest, meal: meal), now: morning)
        XCTAssertEqual(late.next?.kind, .meal)
        XCTAssertEqual(late.next?.title, "Lunch bowl")
        XCTAssertEqual(late.next?.trailing, "12:30")
        XCTAssertEqual(late.next?.detail, "780 kcal · 62 g protein")
        XCTAssertEqual(late.next?.destination, .fuel)
    }

    // MARK: Day handling

    func testEarlierDaysProgressIsNeverShownAsToday() {
        let yesterday = WidgetSnapshot(today: todaySnapshot(), now: today)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let carried = yesterday.carried(to: tomorrow.addingTimeInterval(3600))
        XCTAssertNil(carried.score)
        XCTAssertNil(carried.calories)
        XCTAssertNil(carried.next)
        XCTAssertEqual(carried.waterMl, 0)
        // Targets still hold.
        XCTAssertEqual(carried.calorieTarget, 2600)
        XCTAssertEqual(carried.waterTargetMl, 2900)
        XCTAssertEqual(carried.day, tomorrow)
    }

    func testSameDayIsUnchanged() {
        let snap = WidgetSnapshot(today: todaySnapshot(), now: today.addingTimeInterval(3600))
        XCTAssertEqual(snap.carried(to: today.addingTimeInterval(7200)), snap)
    }

    func testFractionIsClampedAndNeedsATarget() {
        XCTAssertEqual(WidgetSnapshot.fraction(500, of: 2000), 0.25)
        XCTAssertEqual(WidgetSnapshot.fraction(3000, of: 2000), 1)
        XCTAssertNil(WidgetSnapshot.fraction(500, of: nil))
        XCTAssertNil(WidgetSnapshot.fraction(500, of: 0))
        XCTAssertNil(WidgetSnapshot.fraction(nil, of: 2000))
    }

    // MARK: Writing

    func testWriteThenReadRoundTrips() {
        let snap = WidgetSnapshot(today: todaySnapshot(), now: today.addingTimeInterval(3600))
        publish(snap)
        XCTAssertEqual(WidgetSnapshot.read(from: defaults), snap)
    }

    func testNothingWrittenReadsAsNil() {
        XCTAssertNil(WidgetSnapshot.read(from: defaults))
    }

    func testUnchangedSnapshotDoesNotReloadAgain() {
        let first = WidgetSnapshot(today: todaySnapshot(), now: today.addingTimeInterval(3600))
        publish(first)
        var again = first
        again.writtenAt = first.writtenAt.addingTimeInterval(600)
        publish(again)
        XCTAssertEqual(reloads, 1)

        var changed = first
        changed.waterMl += 250
        publish(changed)
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(WidgetSnapshot.read(from: defaults)?.waterMl, first.waterMl + 250)
    }

    // MARK: Water with no screen

    func testRecordWaterPatchesOnlyTheWater() {
        let snap = WidgetSnapshot(today: todaySnapshot(), now: today.addingTimeInterval(3600))
        publish(snap)
        let now = today.addingTimeInterval(7200)
        WidgetSyncService.recordWater(
            totalMl: 1000, targetMl: 2900, now: now, defaults: defaults, reload: { [self] in reloads += 1 }
        )
        let stored = WidgetSnapshot.read(from: defaults)
        XCTAssertEqual(stored?.waterMl, 1000)
        XCTAssertEqual(stored?.score, 81)
        XCTAssertEqual(stored?.calories, 1840)
        XCTAssertEqual(stored?.next?.kind, .workout)
        XCTAssertEqual(reloads, 2)
    }

    func testRecordWaterWithNothingWrittenYetStartsTodayWithOnlyWater() {
        let now = today.addingTimeInterval(3600)
        WidgetSyncService.recordWater(
            totalMl: 250, targetMl: 2500, now: now, defaults: defaults, reload: { [self] in reloads += 1 }
        )
        let stored = WidgetSnapshot.read(from: defaults)
        XCTAssertEqual(stored?.waterMl, 250)
        XCTAssertEqual(stored?.waterTargetMl, 2500)
        XCTAssertNil(stored?.score)
        XCTAssertNil(stored?.calories)
        XCTAssertNil(stored?.next)
        XCTAssertEqual(stored?.day, today)
    }

    func testRecordWaterOnANewDayDropsYesterdaysFigures() {
        let snap = WidgetSnapshot(today: todaySnapshot(), now: today.addingTimeInterval(3600))
        publish(snap)
        let tomorrow = (calendar.date(byAdding: .day, value: 1, to: today) ?? today).addingTimeInterval(3600)
        WidgetSyncService.recordWater(
            totalMl: 250, targetMl: nil, now: tomorrow, defaults: defaults, reload: {}
        )
        let stored = WidgetSnapshot.read(from: defaults)
        XCTAssertEqual(stored?.waterMl, 250)
        XCTAssertNil(stored?.score)
        XCTAssertNil(stored?.calories)
        // The target carries over when the new reading has none.
        XCTAssertEqual(stored?.waterTargetMl, 2900)
    }
}
