//
// TrainerProgramImportBatchingTests.swift
// Tempo
//
// Pure batch-planning tests (fix #2) — no network, no UIKit. Exercises the
// exact grouping the multi-image TRANSCRIBE step relies on to stay under
// the backend's per-request image count and byte budget.
//

@testable import Tempo
import XCTest

final class TrainerProgramImportBatchingTests: XCTestCase {
    func testGroupsUpToFiveImagesPerBatch() {
        let sizes = Array(repeating: 1000, count: 12)
        let batches = TrainerProgramImportBatching.plan(sizes: sizes, maxImagesPerBatch: 5, maxBatchBytes: 1_000_000)
        XCTAssertEqual(batches.map(\.count), [5, 5, 2])
    }

    func testPreservesOriginalOrderAcrossBatches() {
        let sizes = Array(repeating: 1000, count: 7)
        let batches = TrainerProgramImportBatching.plan(sizes: sizes, maxImagesPerBatch: 3, maxBatchBytes: 1_000_000)
        XCTAssertEqual(batches, [[0, 1, 2], [3, 4, 5], [6]])
    }

    func testStartsANewBatchEarlyWhenByteBudgetWouldBeExceeded() {
        // 3 images of 2MB each: count cap is 5, but only 2 fit under a 4MB budget.
        let twoMB = 2 * 1024 * 1024
        let sizes = [twoMB, twoMB, twoMB]
        let batches = TrainerProgramImportBatching.plan(sizes: sizes, maxImagesPerBatch: 5, maxBatchBytes: 4 * 1024 * 1024)
        XCTAssertEqual(batches, [[0, 1], [2]])
    }

    func testASingleOversizedImageBecomesItsOwnSoloBatch() {
        let sizes = [10 * 1024 * 1024]
        let batches = TrainerProgramImportBatching.plan(sizes: sizes, maxImagesPerBatch: 5, maxBatchBytes: 4 * 1024 * 1024)
        XCTAssertEqual(batches, [[0]])
    }

    func testEmptyInputProducesNoBatches() {
        XCTAssertEqual(TrainerProgramImportBatching.plan(sizes: []), [])
    }

    func testExactlyAtByteBudgetStaysInOneBatch() {
        let sizes = [1_000_000, 1_000_000, 1_000_000, 1_000_000]
        let batches = TrainerProgramImportBatching.plan(sizes: sizes, maxImagesPerBatch: 5, maxBatchBytes: 4_000_000)
        XCTAssertEqual(batches, [[0, 1, 2, 3]])
    }

    func testDefaultsMatchBackendContract() {
        XCTAssertEqual(TrainerProgramImportBatching.maxImagesPerBatch, 5)
        XCTAssertEqual(TrainerProgramImportBatching.maxConcurrentBatches, 2)
    }
}
