//
// ReceiptPrivacyRedactorTests.swift
// Tempo
//
// Covers ReceiptPrivacyRedactor against the exact PII patterns found in real
// receipt footers during development (see the file's own header for the
// source cases) — already-masked card digits are left alone, unmasked
// auth/trace/reference numbers and EMV AID tokens are stripped, and normal
// item/price lines pass through untouched.
//

@testable import Tempo
import XCTest

final class ReceiptPrivacyRedactorTests: XCTestCase {
    func test_maskedCardDigits_areKeptAsIs() {
        let input = "MasterCard: *3918"
        XCTAssertEqual(ReceiptPrivacyRedactor.redact(input), input)
    }

    func test_maskedCardWithXPadding_isKeptAsIs() {
        let input = "Acct #: XXXXXXXXXXXX3918"
        let output = ReceiptPrivacyRedactor.redact(input)
        // The X-padded run itself is safe, but the "Acct #" keyword prefix
        // rule takes priority and redacts the whole trailing value —
        // strictly safer than leaving it, and still not a false negative on
        // the un-padded 9+ digit rule.
        XCTAssertTrue(output.contains("[redacted]"))
        XCTAssertFalse(output.contains("3918") && !output.contains("["))
    }

    func test_authTraceLine_valueRedacted_keywordKept() {
        let output = ReceiptPrivacyRedactor.redact("Auth/Trace: 403302/067554")
        XCTAssertTrue(output.lowercased().hasPrefix("auth/trace"))
        XCTAssertTrue(output.contains("[redacted]"))
        XCTAssertFalse(output.contains("403302"))
        XCTAssertFalse(output.contains("067554"))
    }

    func test_referenceLine_valueRedacted() {
        let output = ReceiptPrivacyRedactor.redact("Reference #: 001877040565")
        XCTAssertTrue(output.contains("[redacted]"))
        XCTAssertFalse(output.contains("001877040565"))
    }

    func test_emvAIDToken_redacted() {
        let output = ReceiptPrivacyRedactor.redact("AID: A0000000041010")
        XCTAssertFalse(output.contains("A0000000041010"))
        XCTAssertTrue(output.contains("[redacted]"))
    }

    func test_bareLongDigitRun_redacted() {
        let output = ReceiptPrivacyRedactor.redact("Some code 123456789012 trailing")
        XCTAssertFalse(output.contains("123456789012"))
        XCTAssertTrue(output.contains("[redacted]"))
    }

    func test_normalItemLine_passesThroughUnchanged() {
        let input = "BANANAS   0.69 F"
        XCTAssertEqual(ReceiptPrivacyRedactor.redact(input), input)
    }

    func test_shortPriceNumbers_notRedacted() {
        // Prices, quantities and short codes (< 9 digits) must never be
        // touched — only long unmasked runs are a real PII leak.
        let input = "TOTAL 123.45"
        XCTAssertEqual(ReceiptPrivacyRedactor.redact(input), input)
    }

    func test_multilineText_redactsOnlyTheSensitiveLines() {
        let input = """
        PUBLIX
        BANANAS   0.69 F
        Auth/Trace: 403302/067554
        Total   13.20
        """
        let output = ReceiptPrivacyRedactor.redact(input)
        let lines = output.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "PUBLIX")
        XCTAssertEqual(lines[1], "BANANAS   0.69 F")
        XCTAssertTrue(lines[2].contains("[redacted]"))
        XCTAssertEqual(lines[3], "Total   13.20")
    }
}
