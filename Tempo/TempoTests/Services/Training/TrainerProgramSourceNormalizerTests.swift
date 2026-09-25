//
// TrainerProgramSourceNormalizerTests.swift
// Tempo
//
// Pins the NORMALIZE step of the Trainer Program import pipeline: content-
// type routing (which file extensions need PDFKit vs. a WKWebView
// conversion vs. plain text — the WKWebView conversion itself needs a real
// WebKit render pass and isn't unit-testable, so this covers the routing
// DECISION instead), the page cap, and direct-text passthrough (pasted
// text/.txt/.csv skip vision transcription entirely).
//

@testable import Tempo
import UniformTypeIdentifiers
import XCTest

@MainActor
final class TrainerProgramSourceNormalizerTests: XCTestCase {
    // MARK: - Content-type routing

    func testPDFRoutesToPDFKind() {
        XCTAssertEqual(
            TrainerProgramSourceNormalizer.routingKind(for: URL(fileURLWithPath: "/tmp/lift.pdf")),
            .pdf
        )
    }

    func testImageExtensionsRouteToImageKind() {
        for ext in ["jpg", "jpeg", "png", "heic"] {
            XCTAssertEqual(
                TrainerProgramSourceNormalizer.routingKind(for: URL(fileURLWithPath: "/tmp/sheet.\(ext)")),
                .image,
                "\(ext) should route to .image"
            )
        }
    }

    func testPlainTextAndCSVRouteToTextKind() {
        XCTAssertEqual(
            TrainerProgramSourceNormalizer.routingKind(for: URL(fileURLWithPath: "/tmp/program.txt")),
            .text
        )
        XCTAssertEqual(
            TrainerProgramSourceNormalizer.routingKind(for: URL(fileURLWithPath: "/tmp/program.csv")),
            .text
        )
    }

    func testOfficeAndMarkupFormatsRouteToOfficeConvertible() {
        for ext in ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "rtf", "html"] {
            XCTAssertEqual(
                TrainerProgramSourceNormalizer.routingKind(for: URL(fileURLWithPath: "/tmp/program.\(ext)")),
                .officeConvertible,
                "\(ext) should route to .officeConvertible"
            )
        }
    }

    func testUnknownExtensionFallsBackToOfficeConvertible() {
        XCTAssertEqual(
            TrainerProgramSourceNormalizer.routingKind(for: URL(fileURLWithPath: "/tmp/program.weirdext")),
            .officeConvertible
        )
    }

    func testAllowedContentTypesCoversEveryRoutedFormat() {
        let types = TrainerProgramSourceNormalizer.allowedContentTypes
        XCTAssertTrue(types.contains(.pdf))
        XCTAssertTrue(types.contains(.image))
        XCTAssertTrue(types.contains(.plainText))
        XCTAssertTrue(types.contains(.commaSeparatedText))
        XCTAssertTrue(types.contains(.rtf))
        XCTAssertTrue(types.contains(.html))
        XCTAssertFalse(types.isEmpty)
    }

    // MARK: - Direct-text sources (pasted text — no vision call)

    func testPastedTextBecomesDirectTextUnit() async throws {
        let sources = [ProgramImportSource(displayName: "Pasted", payload: .pastedText("Squat 3x5\nBench 3x5"))]
        let units = try await TrainerProgramSourceNormalizer.normalize(sources)
        XCTAssertEqual(units.count, 1)
        guard case let .directText(text, label) = units[0] else {
            return XCTFail("expected .directText")
        }
        XCTAssertEqual(text, "Squat 3x5\nBench 3x5")
        XCTAssertEqual(label, "Pasted")
    }

    func testMultipleSourcesPreserveOrder() async throws {
        let sources = [
            ProgramImportSource(displayName: "First", payload: .pastedText("A")),
            ProgramImportSource(displayName: "Second", payload: .pastedText("B")),
        ]
        let units = try await TrainerProgramSourceNormalizer.normalize(sources)
        XCTAssertEqual(units.map(\.sourceLabel), ["First", "Second"])
    }

    func testBlankPastedTextThrowsUnreadableSource() async {
        let sources = [ProgramImportSource(displayName: "Blank", payload: .pastedText("   \n  "))]
        await assertThrows(try await TrainerProgramSourceNormalizer.normalize(sources)) { error in
            XCTAssertEqual(error as? TrainerProgramSourceNormalizer.NormalizeError, .unreadableSource("Blank"))
        }
    }

    func testNoSourcesThrowsNoSources() async {
        await assertThrows(try await TrainerProgramSourceNormalizer.normalize([])) { error in
            XCTAssertEqual(error as? TrainerProgramSourceNormalizer.NormalizeError, .noSources)
        }
    }

    // MARK: - Page cap

    func testTooManySourcesThrowsPageCapError() async {
        let sources = (1 ... (TrainerProgramSourceNormalizer.maxPages + 5)).map {
            ProgramImportSource(displayName: "Day \($0)", payload: .pastedText("Squat 3x5"))
        }
        await assertThrows(try await TrainerProgramSourceNormalizer.normalize(sources)) { error in
            XCTAssertEqual(
                error as? TrainerProgramSourceNormalizer.NormalizeError,
                .tooManyPages(TrainerProgramSourceNormalizer.maxPages)
            )
        }
    }

    func testExactlyMaxPagesDoesNotThrow() async throws {
        let sources = (1 ... TrainerProgramSourceNormalizer.maxPages).map {
            ProgramImportSource(displayName: "Day \($0)", payload: .pastedText("Squat 3x5"))
        }
        let units = try await TrainerProgramSourceNormalizer.normalize(sources)
        XCTAssertEqual(units.count, TrainerProgramSourceNormalizer.maxPages)
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expression: @autoclosure () async throws -> some Any,
        _ errorHandler: (Error) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail("expected an error to be thrown")
        } catch {
            errorHandler(error)
        }
    }
}
