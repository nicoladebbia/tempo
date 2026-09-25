//
// TrainerProgramPageTranscriberTests.swift
// Tempo
//
// Pins the TRANSCRIBE step's prompt contract, retry policy, and the
// batching/resume orchestration (fix #2) — the last of which is driven with
// a fake `send`/`sleep` so it runs instantly with no real network and no
// real delays. Batches run concurrently (task group), so shared test state
// is guarded with `LockedBox` (os_unfair_lock — safe from both sync and
// async call sites, unlike NSLock which the Swift 6 concurrency checker
// flags as unavailable inside an async function body).
//

import os
@testable import Tempo
import XCTest

// MARK: - LockedBox

/// Minimal thread-safe mutable box for collecting results from concurrently
/// executing fake network closures in these tests.
private final class LockedBox<Value>: @unchecked Sendable {
    private var unfairLock = os_unfair_lock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        return body(&value)
    }

    var snapshot: Value {
        withLock { $0 }
    }
}

// MARK: - TrainerProgramPageTranscriberTests

final class TrainerProgramPageTranscriberTests: XCTestCase {
    // MARK: - Prompts (pure)

    func testBatchUserMessageAsksForRowByRowTranscription() {
        let message = TrainerProgramPageTranscriber.batchUserMessage(pageCount: 3)
        XCTAssertTrue(message.contains("row by row"))
        XCTAssertTrue(message.contains("A | Leg Press | 3 x 8"))
    }

    func testBatchUserMessageForMultiplePagesAsksForNumberedSentinels() {
        let message = TrainerProgramPageTranscriber.batchUserMessage(pageCount: 3)
        XCTAssertTrue(message.contains("=== PAGE n ==="))
        XCTAssertTrue(message.contains("3 images"))
    }

    func testBatchUserMessageForOnePageStillAsksForTheSentinel() {
        let message = TrainerProgramPageTranscriber.batchUserMessage(pageCount: 1)
        XCTAssertTrue(message.contains("=== PAGE 1 ==="))
    }

    func testSystemPromptDoesNotAskToStructureOrTranslate() {
        XCTAssertTrue(TrainerProgramPageTranscriber.systemPrompt.contains("do not"))
        XCTAssertTrue(TrainerProgramPageTranscriber.systemPrompt.contains("structure"))
    }

    // MARK: - Retry policy (pure)

    func testRetryDelayHonorsRetryAfterOverBackoffTable() {
        XCTAssertEqual(TrainerProgramPageTranscriber.retryDelay(attempt: 0, retryAfter: 15), 15)
    }

    func testRetryDelayFallsBackTo2_4_8SecondsWithNoRetryAfter() {
        XCTAssertEqual(TrainerProgramPageTranscriber.retryDelay(attempt: 0, retryAfter: nil), 2)
        XCTAssertEqual(TrainerProgramPageTranscriber.retryDelay(attempt: 1, retryAfter: nil), 4)
        XCTAssertEqual(TrainerProgramPageTranscriber.retryDelay(attempt: 2, retryAfter: nil), 8)
    }

    func testRetryDelayGivesUpAfterMaxRetries() {
        XCTAssertEqual(TrainerProgramPageTranscriber.maxRetriesPerBatch, 3)
        XCTAssertNil(TrainerProgramPageTranscriber.retryDelay(attempt: 3, retryAfter: nil))
        XCTAssertNil(TrainerProgramPageTranscriber.retryDelay(attempt: 3, retryAfter: 5))
    }

    // MARK: - Orchestration (fake send/sleep — no network, no real delays)

    private func page(_ label: String, bytes: Int = 100) -> ProgramNormalizedUnit {
        .page(imageJPEG: Data(repeating: 0xFF, count: bytes), hintText: nil, sourceLabel: label)
    }

    func testDirectTextUnitsSkipTranscriptionEntirely() async throws {
        let units: [ProgramNormalizedUnit] = [.directText("Already legible text", sourceLabel: "pasted")]
        let sendCallCount = LockedBox(0)
        let result = try await TrainerProgramPageTranscriber.transcribe(
            units: units,
            onProgress: { _, _, _ in },
            sleep: { _ in },
            send: { batch in
                sendCallCount.withLock { $0 += 1 }
                return batch.map { _ in "unused" }
            }
        )
        XCTAssertEqual(result, "Already legible text")
        XCTAssertEqual(sendCallCount.snapshot, 0)
    }

    func testBatchesUpToFivePagesIntoOneSendCall() async throws {
        let units = (1 ... 5).map { page("Page \($0)") }
        let sendCallCount = LockedBox(0)
        let batchSizesSeen = LockedBox<[Int]>([])
        let result = try await TrainerProgramPageTranscriber.transcribe(
            units: units,
            onProgress: { _, _, _ in },
            sleep: { _ in },
            send: { batch in
                sendCallCount.withLock { $0 += 1 }
                batchSizesSeen.withLock { $0.append(batch.count) }
                return batch.enumerated().map { index, _ in "text \(index)" }
            }
        )
        XCTAssertEqual(sendCallCount.snapshot, 1, "5 pages fit in ONE batch — must be a single network call")
        XCTAssertEqual(batchSizesSeen.snapshot, [5])
        XCTAssertTrue(result.contains("text 0"))
        XCTAssertTrue(result.contains("text 4"))
    }

    func testMoreThanFivePagesSpansMultipleBatches() async throws {
        let units = (1 ... 7).map { page("Page \($0)") }
        let batchSizesSeen = LockedBox<[Int]>([])
        _ = try await TrainerProgramPageTranscriber.transcribe(
            units: units,
            onProgress: { _, _, _ in },
            sleep: { _ in },
            send: { batch in
                batchSizesSeen.withLock { $0.append(batch.count) }
                return batch.map { _ in "x" }
            }
        )
        XCTAssertEqual(batchSizesSeen.snapshot.sorted(), [2, 5])
    }

    func testResultsPreserveOriginalPageOrderRegardlessOfBatchCompletionOrder() async throws {
        let units = (1 ... 6).map { page("Page \($0)") }
        let result = try await TrainerProgramPageTranscriber.transcribe(
            units: units,
            onProgress: { _, _, _ in },
            sleep: { _ in },
            send: { batch in
                // The lone second batch (page 6) "resolves faster" than the
                // 5-page first batch would in a real race — the FINAL joined
                // transcript must still follow original page order, not
                // completion order.
                if batch.count == 1 {
                    try? await Task.sleep(nanoseconds: 1000)
                }
                return batch.map { "content-\($0.sourceLabel)" }
            }
        )
        let indexOfPage1 = result.range(of: "content-Page 1")?.lowerBound
        let indexOfPage6 = result.range(of: "content-Page 6")?.lowerBound
        XCTAssertNotNil(indexOfPage1)
        XCTAssertNotNil(indexOfPage6)
        if let indexOfPage1, let indexOfPage6 {
            XCTAssertLessThan(indexOfPage1, indexOfPage6)
        }
    }

    func testRetriesOnRateLimitAndKeepsOtherBatchesResults() async throws {
        let units = (1 ... 6).map { page("Page \($0)") }
        let attemptsForFailingBatch = LockedBox(0)
        let sleptDelays = LockedBox<[TimeInterval]>([])

        let result = try await TrainerProgramPageTranscriber.transcribe(
            units: units,
            onProgress: { _, _, _ in },
            sleep: { delay in
                sleptDelays.withLock { $0.append(delay) }
            },
            send: { batch in
                // The batch containing "Page 6" fails twice with 429 (Retry-After
                // 3s), then succeeds — its OWN retries must not re-send the
                // other, unrelated batch.
                if batch.contains(where: { $0.sourceLabel == "Page 6" }) {
                    let thisAttempt = attemptsForFailingBatch.withLock { $0 += 1; return $0 }
                    if thisAttempt < 3 {
                        throw APIError.rateLimited(retryAfter: 3)
                    }
                }
                return batch.map { "content-\($0.sourceLabel)" }
            }
        )

        XCTAssertEqual(attemptsForFailingBatch.snapshot, 3, "should retry exactly until success (2 failures + 1 success)")
        XCTAssertEqual(sleptDelays.snapshot, [3, 3], "must honor Retry-After (3s) rather than the 2/4/8 backoff table")
        XCTAssertTrue(result.contains("content-Page 1"), "the OTHER (never-failing) batch's results must survive untouched")
        XCTAssertTrue(result.contains("content-Page 6"), "the retried batch's eventual success must still be included")
    }

    func testGivesUpAfterMaxRetriesAndThrows() async throws {
        let units = [page("Page 1")]
        let attempts = LockedBox(0)
        do {
            _ = try await TrainerProgramPageTranscriber.transcribe(
                units: units,
                onProgress: { _, _, _ in },
                sleep: { _ in },
                send: { _ in
                    attempts.withLock { $0 += 1 }
                    throw APIError.rateLimited(retryAfter: nil)
                }
            )
            XCTFail("expected the batch to exhaust retries and throw")
        } catch {
            // 1 initial try + 3 retries = 4 total attempts.
            XCTAssertEqual(attempts.snapshot, 4)
        }
    }

    func testUnauthorizedMapsToSignedOutWithoutRetrying() async throws {
        let units = [page("Page 1")]
        let attempts = LockedBox(0)
        do {
            _ = try await TrainerProgramPageTranscriber.transcribe(
                units: units,
                onProgress: { _, _, _ in },
                sleep: { _ in XCTFail("must not retry/sleep on 401") },
                send: { _ in
                    attempts.withLock { $0 += 1 }
                    throw APIError.unauthorized
                }
            )
            XCTFail("expected .signedOut")
        } catch let error as TrainerProgramPageTranscriber.TranscribeError {
            guard case .signedOut = error else {
                XCTFail("expected .signedOut, got \(error)")
                return
            }
            XCTAssertEqual(attempts.snapshot, 1)
        }
    }

    func testProgressReportsPageRangeAtBatchStart() async throws {
        let units = (1 ... 6).map { page("Page \($0)") }
        let reportedRanges = LockedBox<[(start: Int, end: Int, total: Int)]>([])
        _ = try await TrainerProgramPageTranscriber.transcribe(
            units: units,
            onProgress: { start, end, total in
                reportedRanges.withLock { $0.append((start, end, total)) }
            },
            sleep: { _ in },
            send: { batch in batch.map { _ in "x" } }
        )
        let sorted = reportedRanges.snapshot.sorted { $0.start < $1.start }
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].start, 1)
        XCTAssertEqual(sorted[0].end, 5)
        XCTAssertEqual(sorted[0].total, 6)
        XCTAssertEqual(sorted[1].start, 6)
        XCTAssertEqual(sorted[1].end, 6)
    }

    func testMissingPageInResponseFillsAnIllegiblePlaceholderInsteadOfDroppingIt() async throws {
        let units = [page("Page 1"), page("Page 2")]
        let result = try await TrainerProgramPageTranscriber.transcribe(
            units: units,
            onProgress: { _, _, _ in },
            sleep: { _ in },
            // Model only returned ONE page for a 2-image batch.
            send: { _ in ["only one page came back"] }
        )
        XCTAssertTrue(result.contains("only one page came back"))
        XCTAssertTrue(result.contains("[illegible]"))
    }
}
