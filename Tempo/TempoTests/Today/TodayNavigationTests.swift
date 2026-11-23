//
// TodayNavigationTests.swift
// TempoTests
//
// Where the app lands: a notification or shortcut never leaves an older page
// on top of Today, and a double tap never opens the same page twice.
//

@testable import Tempo
import XCTest

@MainActor
final class TodayNavigationTests: XCTestCase {
    private func makeState() -> AppState {
        AppState(authService: AuthService())
    }

    func testOpeningPlainTodayClearsAPageLeftOpen() {
        let state = makeState()
        state.todayPath = [.recovery]
        state.activeTab = .fuel
        state.open(.today)
        XCTAssertEqual(state.activeTab, .today)
        XCTAssertTrue(state.todayPath.isEmpty)
    }

    func testOpeningAnotherTabClearsTodaysStack() {
        let state = makeState()
        state.todayPath = [.lockdown]
        state.open(.train)
        XCTAssertEqual(state.activeTab, .train)
        XCTAssertTrue(state.todayPath.isEmpty)
    }

    func testOpeningARouteShowsExactlyThatRoute() {
        let state = makeState()
        state.todayPath = [.fuel, .body]
        state.open(.today, todayRoute: .recovery)
        XCTAssertEqual(state.todayPath, [.recovery])
        state.openOnToday(.lockdown)
        XCTAssertEqual(state.todayPath, [.lockdown])
    }

    func testADoubleTapNeverPushesTheSamePageTwice() {
        let state = makeState()
        XCTAssertTrue(state.pushOnToday(.recovery))
        XCTAssertFalse(state.pushOnToday(.recovery))
        XCTAssertEqual(state.todayPath, [.recovery])
        // A different page on top is a real push.
        XCTAssertTrue(state.pushOnToday(.fuel))
        XCTAssertEqual(state.todayPath, [.recovery, .fuel])
    }
}
