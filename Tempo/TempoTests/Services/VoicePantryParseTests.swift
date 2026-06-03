//
// VoicePantryParseTests.swift
// Tempo
//
// The Haiku proxy sometimes wraps its JSON in a ```json fence, and a long
// stock-take can truncate the response at the token ceiling mid-object. Both
// broke the device parse (a 25-item fridge list failed entirely). These pin
// the two pure recovery helpers: fence-stripping and partial-array salvage.
//

@testable import Tempo
import XCTest

final class VoicePantryParseTests: XCTestCase {

    // MARK: - Fence stripping

    func testStripsJSONFence() {
        let fenced = "```json\n{\"items\":[]}\n```"
        XCTAssertEqual(VoicePantryService.stripMarkdownFence(fenced), "{\"items\":[]}")
    }

    func testStripsBareFence() {
        let fenced = "```\n{\"a\":1}\n```"
        XCTAssertEqual(VoicePantryService.stripMarkdownFence(fenced), "{\"a\":1}")
    }

    func testLeavesUnfencedUntouched() {
        let plain = "{\"items\":[]}"
        XCTAssertEqual(VoicePantryService.stripMarkdownFence(plain), plain)
    }

    // MARK: - Salvage of a truncated array

    func testSalvagesCompleteObjectsFromTruncatedArray() {
        // Response cut off mid-third-object at the token ceiling.
        let truncated = """
        {"items":[\
        {"name":"butter","quantity":100,"unit":"g"},\
        {"name":"eggs","quantity":5,"unit":"pieces"},\
        {"name":"chick
        """
        let salvaged = VoicePantryService.salvageItemsArray(truncated)
        XCTAssertNotNil(salvaged)
        // The two complete objects survive; the partial third is dropped.
        XCTAssertTrue(salvaged!.contains("butter"))
        XCTAssertTrue(salvaged!.contains("eggs"))
        XCTAssertFalse(salvaged!.contains("chick"))
        // And the salvaged string is valid JSON that decodes.
        let data = salvaged!.data(using: .utf8)!
        XCTAssertNoThrow(try JSONDecoder().decode(SalvageProbe.self, from: data))
    }

    func testSalvageHandlesBracesInsideStrings() {
        // A brand containing a brace must not desync the depth counter.
        let truncated = #"{"items":[{"name":"jam","brand":"weird {brand}","quantity":1,"unit":"jars"},{"name":"trunc"#
        let salvaged = VoicePantryService.salvageItemsArray(truncated)
        XCTAssertNotNil(salvaged)
        XCTAssertTrue(salvaged!.contains("weird {brand}"))
        XCTAssertFalse(salvaged!.contains("trunc"))
    }

    func testSalvageReturnsNilWhenNoCompleteObject() {
        XCTAssertNil(VoicePantryService.salvageItemsArray("{\"items\":[{\"name\":\"x"))
    }

    private struct SalvageProbe: Decodable {
        struct Item: Decodable { let name: String }
        let items: [Item]
    }
}
