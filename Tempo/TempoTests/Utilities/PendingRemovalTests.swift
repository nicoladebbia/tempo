//
// PendingRemovalTests.swift
// Tempo
//
// The Undo window rule: an item is hidden at once, comes back on Undo, and is
// removed for good exactly once when the window ends. One item waits at a time.
// The photo cases run the rule against real files in a temporary folder.
//

@testable import Tempo
import XCTest

final class PendingRemovalTests: XCTestCase {
    func testBeginHidesTheItemAndFinishHandsItBackOnce() {
        var pending = PendingRemoval<String>()
        XCTAssertNil(pending.begin("a"))
        XCTAssertTrue(pending.hides("a"))
        XCTAssertFalse(pending.hides("b"))

        XCTAssertEqual(pending.finish(), "a")
        XCTAssertFalse(pending.hides("a"))
        // The window ending twice (toast gone, then the page leaves) removes nothing more.
        XCTAssertNil(pending.finish())
    }

    func testUndoBringsTheItemBackAndNothingIsLeftToRemove() {
        var pending = PendingRemoval<String>()
        pending.begin("a")
        XCTAssertEqual(pending.undo(), "a")
        XCTAssertFalse(pending.hides("a"))
        // The toast then ends: there is nothing to commit.
        XCTAssertNil(pending.finish())
    }

    func testASecondRemovalMakesTheFirstFinal() {
        var pending = PendingRemoval<String>()
        pending.begin("a")
        XCTAssertEqual(pending.begin("b"), "a")
        XCTAssertTrue(pending.hides("b"))
        XCTAssertFalse(pending.hides("a"))

        // Undo now only concerns the second one.
        XCTAssertEqual(pending.undo(), "b")
        XCTAssertNil(pending.finish())
    }

    func testUndoWithNothingPendingDoesNothing() {
        var pending = PendingRemoval<String>()
        XCTAssertNil(pending.undo())
        XCTAssertNil(pending.finish())
    }

    // MARK: Progress photos

    private var folder: URL!
    private var store: ProgressPhotoStore!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "PendingRemovalTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = ProgressPhotoStore(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func addPhoto(daysAgo: Int) throws -> ProgressPhoto {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return try store.add(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]), date: date)
    }

    func testAPhotoInItsUndoWindowIsHiddenButItsFileIsStillThere() throws {
        let kept = try addPhoto(daysAgo: 2)
        let removed = try addPhoto(daysAgo: 1)
        var pending = PendingRemoval<ProgressPhoto>()
        pending.begin(removed)

        let shown = store.photos().filter { !pending.hides($0) }
        XCTAssertEqual(shown.map(\.id), [kept.id])
        // The file is untouched, so Undo has something to bring back.
        XCTAssertTrue(FileManager.default.fileExists(atPath: removed.url.path))
        XCTAssertEqual(store.photos().count, 2)
    }

    func testUndoKeepsThePhotoFileAndShowsItAgain() throws {
        let photo = try addPhoto(daysAgo: 1)
        var pending = PendingRemoval<ProgressPhoto>()
        pending.begin(photo)
        pending.undo()

        // The toast ends after Undo: nothing is deleted.
        if let leftover = pending.finish() {
            try store.delete(leftover)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo.url.path))
        XCTAssertEqual(store.photos().filter { !pending.hides($0) }.count, 1)
    }

    func testTheFileIsDeletedOnlyWhenTheWindowEnds() throws {
        let photo = try addPhoto(daysAgo: 1)
        var pending = PendingRemoval<ProgressPhoto>()
        pending.begin(photo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo.url.path))

        if let final = pending.finish() {
            try store.delete(final)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: photo.url.path))
        XCTAssertTrue(store.photos().isEmpty)
    }

    func testDeletingASecondPhotoDeletesTheFirstFileAndKeepsTheSecondUntilItsWindowEnds() throws {
        let first = try addPhoto(daysAgo: 2)
        let second = try addPhoto(daysAgo: 1)
        var pending = PendingRemoval<ProgressPhoto>()
        pending.begin(first)
        if let replaced = pending.begin(second) {
            try store.delete(replaced)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        XCTAssertTrue(pending.hides(second))
    }
}
