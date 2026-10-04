import Foundation

// MARK: - Non-Claude fixtures (test mode)

//
// USDA, Open Food Facts, DSLD, OpenAI images and Whoop answers for
// TestModeClient. Shapes mirror the DTOs that decode them (USDAClient,
// SupplementLookupClient, OpenAIImageGenerator, WhoopAPIService).

extension TestFixtures {
    /// Per-100 g macros for the foods the fake weekly plan uses, plus a few
    /// staples, so the plan pipeline's USDA check finds real matches.
    static let foods: [(name: String, kcal: Double, protein: Double, carbs: Double, fat: Double)] = [
        ("oats", 379, 13.2, 67.7, 6.5),
        ("greek yogurt", 59, 10.3, 3.6, 0.4),
        ("banana", 89, 1.1, 22.8, 0.3),
        ("blueberries", 57, 0.7, 14.5, 0.3),
        ("eggs", 143, 12.6, 0.7, 9.5),
        ("whole wheat bread", 252, 12.5, 42.7, 3.5),
        ("peanut butter", 588, 25.1, 20, 50.4),
        ("chicken breast", 165, 31, 0, 3.6),
        ("white rice", 130, 2.7, 28.2, 0.3),
        ("broccoli", 34, 2.8, 6.6, 0.4),
        ("olive oil", 884, 0, 0, 100),
        ("salmon", 208, 20.4, 0, 13.4),
        ("sweet potato", 86, 1.6, 20.1, 0.1),
        ("spinach", 23, 2.9, 3.6, 0.4),
        ("lean ground beef", 176, 20, 0, 10),
        ("pasta", 158, 5.8, 30.9, 0.9),
        ("tomato sauce", 29, 1.3, 6.3, 0.2),
        ("cottage cheese", 98, 11.1, 3.4, 4.3),
        ("almonds", 579, 21.2, 21.6, 49.9),
        ("apple", 52, 0.3, 13.8, 0.2),
        ("black beans", 132, 8.9, 23.7, 0.5),
        ("flour tortilla", 312, 8.3, 51.6, 7.9),
        ("turkey breast", 147, 30.1, 0, 2.1),
        ("milk", 61, 3.2, 4.8, 3.3),
        ("whey protein", 400, 80, 8, 6),
    ]

    static func usdaSearch(query: String) -> String {
        let words = Set(query.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let hits = foods.enumerated().filter { _, food in
            let foodWords = Set(food.name.split(separator: " ").map(String.init))
            return !foodWords.isDisjoint(with: words)
        }
        let rows = hits.map { index, food in
            """
            {"fdcId":\(900_000 + index),"description":"\(food.name.capitalized), test fixture","dataType":"Foundation",            "foodNutrients":[{"nutrientId":1008,"value":\(food.kcal)},{"nutrientId":1003,"value":\(food.protein)},            {"nutrientId":1005,"value":\(food.carbs)},{"nutrientId":1004,"value":\(food.fat)}]}
            """
        }
        return #"{"totalHits":"# + "\(rows.count)" + #","foods":["# + rows.joined(separator: ",") + "]}"
    }

    /// Any barcode ending in 0 is "not found"; everything else is a creatine tub.
    static func openFoodFactsProduct(path: String) -> String {
        if path.hasSuffix("0.json") {
            return #"{"status":0,"status_verbose":"product not found"}"#
        }
        return #"""
        {"status":1,"product":{"product_name":"Creatine Monohydrate (test)","brands":"Test Labs","categories":"Dietary supplements, Creatine",        "ingredients_text":"Creatine monohydrate. NSF Certified for Sport.","serving_size":"5 g","quantity":"500 g",        "labels_tags":["en:nsf-certified-for-sport"],"nutriments":{"proteins_serving":0}}}
        """#
    }

    static let dsldSearch = #"{"hits":[{"_id":"999001"}]}"#

    /// DSLD name search (no quoted barcode phrase): one Test Labs creatine tub, with its display fields.
    static let dsldNameSearch = #"{"hits":[{"_id":"999001","_source":{"brandName":"Test Labs","fullName":"Creatine Monohydrate Powder","offMarket":0}}]}"#

    /// Open Food Facts text search (`cgi/search.pl`): a supplement and a non-supplement,
    /// so the "supplements first" ranking is visible in test mode. Both barcodes open
    /// through `openFoodFactsProduct` (they don't end in 0).
    static let openFoodFactsSearch = #"{"count":2,"products":[{"code":"5060000000019","product_name":"Test Cereal Bar","brands":"Test Foods","quantity":"40 g","categories_tags":["en:snacks"]},{"code":"5060000000026","product_name":"Whey Protein (test)","brands":"Test Labs","quantity":"900 g","categories_tags":["en:dietary-supplements","en:protein-powders"]}]}"#

    static let dsldLabel = #"""
    {"brandName":"Test Labs","fullName":"Creatine Monohydrate Powder","productType":{"langualCodeDescription":"Non-Nutrient/Non-Botanical"},    "servingsPerContainer":100,"servingSizes":[{"minQuantity":5,"unit":"Gram(s)","notes":"1 scoop (5 g)"}],    "ingredientRows":[{"name":"Creatine Monohydrate","category":"non-nutrient/non-botanical","quantity":[{"quantity":5,"unit":"Gram(s)"}]}],    "statements":[{"type":"Seals/Symbols","notes":"NSF Certified for Sport"}]}
    """#

    /// A tiny orange JPEG.
    static let openAIImage = #"{"created":1700000000,"data":[{"b64_json":"/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAACKADAAQAAAABAAAACAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgACAAIAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A6yiiiv8AMc/1MP/Z"}]}"#

    static func whoop(path: String) -> String {
        if path.contains("oauth") {
            return #"{"access_token":"test-whoop-access","refresh_token":"test-whoop-refresh","expires_in":3600,"scope":"offline read:recovery read:sleep read:workout read:cycles","token_type":"bearer"}"#
        }
        if path.contains("user/profile") {
            return #"{"user_id":10001,"email":"athlete@test.local","first_name":"Test","last_name":"Athlete"}"#
        }
        return #"{"records":[],"next_token":null}"#
    }
}
