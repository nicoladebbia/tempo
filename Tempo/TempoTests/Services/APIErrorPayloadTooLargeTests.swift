//
// APIErrorPayloadTooLargeTests.swift
// Tempo
//
// Covers the 413 → .payloadTooLarge classification added to fix the receipt
// scan. Before this, 413 fell through to .unknown(statusCode:) and surfaced a
// generic "something went wrong" — the user had no idea the image was too big.
//

@testable import Tempo
import Foundation
import XCTest

final class APIErrorPayloadTooLargeTests: XCTestCase {

    func test_payloadTooLarge_hasActionableUserMessage() {
        // Must NOT be the generic "something went wrong" string — the whole
        // point is telling the user the image is too large.
        let msg = APIError.payloadTooLarge.userMessage
        XCTAssertFalse(msg.lowercased().contains("something went wrong"))
        XCTAssertTrue(
            msg.lowercased().contains("too large") || msg.lowercased().contains("crop"),
            "message should point at the image size, got: \(msg)"
        )
    }

    func test_payloadTooLarge_isNotBlindlyRetryable() {
        // A blind transport-level retry sends the SAME oversized body → same
        // 413. Retry only helps after the caller shrinks the payload, so the
        // transport layer must report it as non-retryable.
        XCTAssertFalse(APIError.payloadTooLarge.isRetryable)
    }
}
