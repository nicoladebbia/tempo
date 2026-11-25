//
// ToastTests.swift
// Tempo
//
// The shared toast: it counts itself in `ToastPresence` (so a first-time tip steps aside), clears
// itself after its duration, and keeps its room for a moment afterwards so a late tap on where
// Undo was lands on nothing.
//

import SwiftUI
@testable import Tempo
import XCTest

// MARK: - ToastBox

@Observable
@MainActor
private final class ToastBox {
    var toast: ToastData?
}

// MARK: - ToastHarness

private struct ToastHarness: View {
    let box: ToastBox

    var body: some View {
        Color.clear.tempoToast(Binding(get: { box.toast }, set: { box.toast = $0 }))
    }
}

// MARK: - ToastTests

@MainActor
final class ToastTests: XCTestCase {
    func testPresenceCountsEveryToastAndNeverGoesBelowZero() {
        let presence = ToastPresence()
        XCTAssertFalse(presence.isUp)
        presence.enter()
        presence.enter()
        XCTAssertTrue(presence.isUp)
        presence.leave()
        XCTAssertTrue(presence.isUp, "one toast is still up")
        presence.leave()
        presence.leave()
        XCTAssertFalse(presence.isUp)
        XCTAssertEqual(presence.count, 0)
    }

    func testAToastWithAnActionStaysLongerThanOneWithout() {
        let plain = ToastData(message: "Saved", style: .success)
        let undoable = ToastData(message: "Deleted", style: .info, actionTitle: "Undo") {}
        XCTAssertGreaterThan(undoable.duration, plain.duration)
        XCTAssertTrue(undoable.spokenText.contains("Undo"))
        XCTAssertEqual(plain.spokenText, "Saved")
    }

    func testTheRoomOutlastsALateTapButNotForLong() {
        // Long enough to cover a thumb that was already on its way to Undo, short enough not to feel stuck.
        XCTAssertGreaterThanOrEqual(ToastSlot.shield, .milliseconds(400))
        XCTAssertLessThanOrEqual(ToastSlot.shield, .seconds(1))
    }

    func testAShownToastClearsItselfAndHoldsItsRoomBriefly() async throws {
        let box = ToastBox()
        let before = ToastPresence.shared.count
        box.toast = ToastData(message: "Saved", style: .success)

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        window.rootViewController = UIHostingController(rootView: ToastHarness(box: box))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNotNil(box.toast, "still up")
        XCTAssertEqual(ToastPresence.shared.count, before + 1, "the toast is counted while it is up")

        // 3 s for a toast without an action: look just after it goes, well inside the held room.
        let duration = Duration.seconds(ToastData(message: "x", style: .info).duration)
        try await Task.sleep(for: duration - .milliseconds(600) + .milliseconds(200))
        XCTAssertNil(box.toast, "it clears itself")
        XCTAssertEqual(ToastPresence.shared.count, before + 1, "its room is held a moment after it goes")

        try await Task.sleep(for: ToastSlot.shield + .milliseconds(500))
        XCTAssertEqual(ToastPresence.shared.count, before, "then the room closes")
    }
}
