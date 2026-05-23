//
// NotificationSystemTests.swift
// Tempo
//
// Created by Tempo on 19/05/2026.
//
//
// Covers the notification-system extension: daily budget governor + the
// NonNegotiable-deadline override, the 4-tier coaching-intensity mapping,
// the social-hours Focus Timer blocker (window math + once-per-session),
// and the Whoop-overlap guard.
//
// NOTE ON EXECUTION: `xcodebuild test` cannot run in this project — the
// TempoTests target's TEST_HOST resolves to `Tempo.app//Tempo` on the iOS
// simulator (`$(BUNDLE_EXECUTABLE_FOLDER_PATH)` is empty), so the test host
// never launches. These tests are written to the project's XCTest
// conventions and compile under `xcodebuild build`; they are not executable
// via xcodebuild until TEST_HOST is fixed (out of scope for this change).

@testable import Tempo
import UserNotifications
import XCTest

final class NotificationSystemTests: XCTestCase {
    // MARK: - Daily Budget Governor

    func testCanSpendBudget_underCap_returnsTrue() {
        let service = NotificationService()
        XCTAssertTrue(service.canSpendBudget(cost: 1.0))
    }

    func testCanSpendBudget_overCap_returnsFalse() {
        let service = NotificationService()
        // dailyBudgetCap is 6.0 — spend up to it, then a further spend is denied.
        service.spendBudget(cost: 6.0)
        XCTAssertFalse(service.canSpendBudget(cost: 0.5))
    }

    func testCanSpendBudget_exactlyAtCap_returnsTrue() {
        let service = NotificationService()
        service.spendBudget(cost: 5.0)
        XCTAssertTrue(service.canSpendBudget(cost: 1.0)) // 5 + 1 == 6, allowed
        XCTAssertFalse(service.canSpendBudget(cost: 1.5)) // 5 + 1.5 > 6, denied
    }

    // MARK: - NonNegotiable Deadline Override

    func testDeadlineOverride_imminentCritical_bypassesBudget() {
        // critical deadline firing in 10 min (< 30 min window) must bypass.
        XCTAssertTrue(
            NotificationService.shouldBypassBudgetForDeadline(
                tier: .critical, secondsUntilFire: 10 * 60
            )
        )
    }

    func testDeadlineOverride_imminentUrgent_bypassesBudget() {
        XCTAssertTrue(
            NotificationService.shouldBypassBudgetForDeadline(
                tier: .urgent, secondsUntilFire: 5 * 60
            )
        )
    }

    func testDeadlineOverride_atExactly30Min_bypassesBudget() {
        // Boundary: 30 min (1800s) is inside the inclusive imminence window.
        XCTAssertTrue(
            NotificationService.shouldBypassBudgetForDeadline(
                tier: .critical, secondsUntilFire: 30 * 60
            )
        )
    }

    func testDeadlineOverride_notImminent_doesNotBypass() {
        // critical but 2 hours out — still budget-governed, not bypassed.
        XCTAssertFalse(
            NotificationService.shouldBypassBudgetForDeadline(
                tier: .critical, secondsUntilFire: 2 * 3600
            )
        )
    }

    func testDeadlineOverride_gentleTierNeverBypasses() {
        // Even imminent, a non-deadline tier stays budget-gated.
        XCTAssertFalse(
            NotificationService.shouldBypassBudgetForDeadline(
                tier: .gentle, secondsUntilFire: 60
            )
        )
        XCTAssertFalse(
            NotificationService.shouldBypassBudgetForDeadline(
                tier: .firm, secondsUntilFire: 60
            )
        )
    }

    // MARK: - Coaching Intensity (4 tiers)

    func testCopyIntensityMapping_allFourTiersDistinct() {
        XCTAssertEqual(CopyIntensity(notificationIntensity: 1), .gentle)
        XCTAssertEqual(CopyIntensity(notificationIntensity: 2), .firm)
        XCTAssertEqual(CopyIntensity(notificationIntensity: 3), .drillSergeant)
        XCTAssertEqual(CopyIntensity(notificationIntensity: 4), .savage)
    }

    func testCopyIntensityMapping_drillSergeantNoLongerCollapsesToFirm() {
        // Regression: pre-change, intensity 3 mapped to .firm. It must now be
        // its own distinct pool.
        XCTAssertNotEqual(CopyIntensity(notificationIntensity: 3), .firm)
        XCTAssertEqual(CopyIntensity(notificationIntensity: 3), .drillSergeant)
    }

    func testCopyIntensityMapping_outOfRangeDefaultsToFirm() {
        XCTAssertEqual(CopyIntensity(notificationIntensity: 0), .firm)
        XCTAssertEqual(CopyIntensity(notificationIntensity: 99), .firm)
    }

    func testCopyIntensityDegradeChain_alwaysHeadsWithSelf() {
        for intensity in CopyIntensity.allCases {
            XCTAssertEqual(intensity.degradeChain.first, intensity,
                           "\(intensity) degrade chain must start with itself")
            XCTAssertFalse(intensity.degradeChain.isEmpty)
        }
    }

    // MARK: - Social-Hours Window Math

    func testSocialWindow_simpleDaytimeWindow() {
        // 09:00–17:00 → 540..1020
        XCTAssertTrue(NotificationService.minutesInWindow(600, start: 540, end: 1020)) // 10:00
        XCTAssertFalse(NotificationService.minutesInWindow(480, start: 540, end: 1020)) // 08:00
        XCTAssertFalse(NotificationService.minutesInWindow(1020, start: 540, end: 1020)) // 17:00 == end, excluded
    }

    func testSocialWindow_defaultEveningWindow() {
        // Default social window 19:30 (1170) → 23:00 (1380).
        XCTAssertTrue(NotificationService.minutesInWindow(1200, start: 1170, end: 1380)) // 20:00
        XCTAssertFalse(NotificationService.minutesInWindow(1100, start: 1170, end: 1380)) // 18:20
    }

    func testSocialWindow_wrapsPastMidnight() {
        // 22:00 (1320) → 02:00 (120).
        XCTAssertTrue(NotificationService.minutesInWindow(1380, start: 1320, end: 120)) // 23:00
        XCTAssertTrue(NotificationService.minutesInWindow(60, start: 1320, end: 120)) // 01:00
        XCTAssertFalse(NotificationService.minutesInWindow(600, start: 1320, end: 120)) // 10:00
    }

    func testSocialWindow_zeroWidthWindowNeverMatches() {
        XCTAssertFalse(NotificationService.minutesInWindow(720, start: 720, end: 720))
    }

    func testMinutesSinceWindowStart_handlesMidnightWrap() {
        // Window opened 22:00 (1320); now 01:00 (60) → 180 min elapsed.
        XCTAssertEqual(NotificationService.minutesSinceWindowStart(60, start: 1320), 180)
        // Same-day: opened 19:30 (1170), now 20:00 (1200) → 30 min.
        XCTAssertEqual(NotificationService.minutesSinceWindowStart(1200, start: 1170), 30)
    }

    // MARK: - Social Blocker: once per Focus Timer session

    func testSocialBlocker_firesAtMostOncePerSession() {
        let service = NotificationService()
        // A time guaranteed to be inside a full-day window so the only
        // suppression under test is the once-per-session guard.
        let first = service.scheduleSocialBlockerIfNeeded(
            sessionID: "session-A",
            enabled: true,
            windowStartMinutes: 0,
            windowEndMinutes: 1439,
            notificationIntensity: 3
        )
        let second = service.scheduleSocialBlockerIfNeeded(
            sessionID: "session-A",
            enabled: true,
            windowStartMinutes: 0,
            windowEndMinutes: 1439,
            notificationIntensity: 3
        )
        XCTAssertTrue(first, "First blocker for a session should fire")
        XCTAssertFalse(second, "Second blocker for the same session must be suppressed")
    }

    func testSocialBlocker_differentSessionFiresAgain() {
        let service = NotificationService()
        _ = service.scheduleSocialBlockerIfNeeded(
            sessionID: "session-A", enabled: true,
            windowStartMinutes: 0, windowEndMinutes: 1439, notificationIntensity: 3
        )
        let other = service.scheduleSocialBlockerIfNeeded(
            sessionID: "session-B", enabled: true,
            windowStartMinutes: 0, windowEndMinutes: 1439, notificationIntensity: 3
        )
        XCTAssertTrue(other, "A distinct session should get its own blocker")
    }

    func testSocialBlocker_disabledNeverFires() {
        let service = NotificationService()
        let fired = service.scheduleSocialBlockerIfNeeded(
            sessionID: "session-C", enabled: false,
            windowStartMinutes: 0, windowEndMinutes: 1439, notificationIntensity: 3
        )
        XCTAssertFalse(fired)
    }

    func testSocialBlocker_outsideWindowNeverFires() {
        let service = NotificationService()
        // Force a zero-width window so "now" can never be inside it.
        let fired = service.scheduleSocialBlockerIfNeeded(
            sessionID: "session-D", enabled: true,
            windowStartMinutes: 600, windowEndMinutes: 600, notificationIntensity: 3
        )
        XCTAssertFalse(fired)
    }

    // MARK: - Whoop Overlap Guard

    func testRescheduleAllForToday_acceptsOnlyEscalationsAndMeals() {
        // Compile-time guard: the orchestrator signature no longer accepts
        // briefing / briefingTime / bedtime. If a Whoop-overlap parameter were
        // reintroduced this call would fail to compile.
        let service = NotificationService()
        service.rescheduleAllForToday(escalations: [], meals: [])
    }

    func testRescheduleAllForToday_schedulesNoWhoopOverlapCategories() {
        // Runtime guard: after a reschedule with no inputs, none of the
        // Whoop-overlap categories (morning briefing, bedtime, recovery) are
        // pending. (Executable only once TEST_HOST is fixed — see file header.)
        let service = NotificationService()
        service.rescheduleAllForToday(escalations: [], meals: [])

        let expectation = expectation(description: "pending requests fetched")
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let whoopCategories: Set<String> = [
                "MORNING_BRIEFING", "BEDTIME_REMINDER", "RECOVERY_REPORT",
            ]
            let offenders = requests
                .map(\.content.categoryIdentifier)
                .filter(whoopCategories.contains)
            XCTAssertTrue(
                offenders.isEmpty,
                "Whoop-overlap notifications must never be scheduled, found: \(offenders)"
            )
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
}
