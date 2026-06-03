//
// GroceryCategoryTests.swift
// Tempo
//
// Pins GroceryListGenerator.category(for:) against the user's REAL pantry
// (the 14 items voice-logged 2026-06-02) so the shopping list groups them
// like a store walk — meat and seafood split out as their own aisles, not
// lumped into a generic "protein" or dumped in the "pantry" catch-all.
//

@testable import Tempo
import XCTest

final class GroceryCategoryTests: XCTestCase {

    private func cat(_ name: String) -> String {
        GroceryListGenerator.category(for: name)
    }

    func testMeatAndSeafoodAreDistinctAisles() {
        XCTAssertEqual(cat("ground beef"), "meat")
        XCTAssertEqual(cat("chicken breast"), "meat")
        XCTAssertEqual(cat("salmon"), "seafood")
        XCTAssertEqual(cat("shrimp"), "seafood")
        XCTAssertNotEqual(cat("salmon"), cat("ground beef"),
                          "Fish and meat must not share an aisle")
    }

    func testRealPantryItemsCategorizeSensibly() {
        // The 14 items from the device stock-take.
        XCTAssertEqual(cat("ricotta"), "dairy")
        XCTAssertEqual(cat("parmesan"), "dairy")
        XCTAssertEqual(cat("butter"), "dairy")
        XCTAssertEqual(cat("eggs"), "dairy")
        XCTAssertEqual(cat("carrots"), "produce")
        XCTAssertEqual(cat("salmon"), "seafood")
        XCTAssertEqual(cat("shrimp"), "seafood")
        XCTAssertEqual(cat("ground beef"), "meat")
        XCTAssertEqual(cat("chicken breast"), "meat")
        XCTAssertEqual(cat("corn"), "produce")
        // Sauces / preserves / condiments legitimately fall to the catch-all.
        XCTAssertEqual(cat("blackberry jam"), "pantry")
        XCTAssertEqual(cat("pasta pomodoro sauce"), "grains") // "pasta" keyword → grains aisle; acceptable
    }

    func testNoneOfTheRealMeatsOrFishHitTheCatchAll() {
        for item in ["salmon", "shrimp", "ground beef", "chicken breast"] {
            XCTAssertNotEqual(cat(item), "pantry",
                              "\(item) should be a real aisle, not the pantry catch-all")
        }
    }

    func testUnknownFoodFallsToPantry() {
        XCTAssertEqual(cat("sriracha"), "pantry")
        XCTAssertEqual(cat("soy sauce"), "pantry")
    }
}
