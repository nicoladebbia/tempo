//
// NutritionLabelReader.swift
// Tempo
//
// "Add missing product": the user photographs the nutrition table (and
// optionally the ingredients). Claude Haiku Vision, through the Pro-gated
// nutrition AI proxy, reads it into per-100 g values; E-numbers in the
// ingredients are picked out locally so the Tempo score can rate additives.
// Everything stays editable on the Add Product screen — without Pro or
// sign-in the user simply types the values.
//

import Foundation

// MARK: - NutritionLabelReading

struct NutritionLabelReading: Equatable, Sendable {
    var name: String?
    var brand: String?
    var servingGrams: Double?
    var per100g: FoodProduct.Nutrients
    var ingredients: String?
    var allergens: [String]
    var additives: [String]
    var isBeverage: Bool
}

// MARK: - NutritionLabelReading_

// MARK: - NutritionLabelReader

enum NutritionLabelReader {
    static let systemPrompt = """
    You read food packaging photos (any language, often Italian) and return \
    ONLY valid JSON, no prose, no code fences. Shape:
    {"name":"<product name or null>","brand":"<brand or null>","serving_g":<number or null>,\
    "is_beverage":<true|false>,\
    "per_100g":{"kcal":<n>,"protein":<n>,"carbs":<n>,"sugars":<n|null>,"fat":<n>,\
    "saturated_fat":<n|null>,"fiber":<n|null>,"salt":<n|null>},\
    "ingredients":"<ingredients text or null>","allergens":["milk","gluten",...]}
    Use the PER 100 g / 100 ml column. If only per-serving values are printed, \
    convert them to per 100 g using the serving weight. kcal = energy in kcal \
    (convert from kJ ÷ 4.184 if needed). Salt in grams (sodium × 2.5). \
    Allergen names in English lowercase (milk, gluten, eggs, soybeans, nuts, \
    peanuts, sesame-seeds, fish, crustaceans, molluscs, celery, mustard, lupin, \
    sulphur-dioxide-and-sulphites). Use null for anything you can't read.
    """

    @MainActor
    static func read(imageJPEG: Data, apiClient: APIClient) async throws -> NutritionLabelReading {
        let body = NutritionProxyVisionRequest(
            model: "haiku",
            system: systemPrompt,
            userMessage: "Read this product's nutrition label and ingredients.",
            imageMediaType: "image/jpeg",
            imageBase64: PhotoAnalysisService.downsampledBase64(imageJPEG),
            maxTokens: 900,
            temperature: 0,
            caller: "food_label_reader"
        )
        let response: NutritionProxyTextResponse = try await apiClient.request(.nutritionProxyVision(), body: body)
        return try parse(response.text)
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case unreadable

        var errorDescription: String? {
            "Couldn't read the label. Try a sharper, closer photo — or type the values."
        }
    }

    static func parse(_ raw: String) throws -> NutritionLabelReading {
        guard let json = TrainerProgramParser.extractJSON(from: raw),
              let data = json.data(using: .utf8),
              let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let per = wire.per100g, per.kcal != nil
        else {
            throw ParseError.unreadable
        }
        let ingredients = wire.ingredients?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NutritionLabelReading(
            name: wire.name?.nilIfBlank,
            brand: wire.brand?.nilIfBlank,
            servingGrams: wire.servingG.flatMap { $0 > 0 ? $0 : nil },
            per100g: FoodProduct.Nutrients(
                kcal: per.kcal, protein: per.protein, carbs: per.carbs, sugars: per.sugars,
                fat: per.fat, saturatedFat: per.saturatedFat, fiber: per.fiber, salt: per.salt
            ),
            ingredients: ingredients?.nilIfBlank,
            allergens: (wire.allergens ?? []).map { $0.lowercased() },
            additives: additiveCodes(in: ingredients ?? ""),
            isBeverage: wire.isBeverage ?? false
        )
    }

    /// "E330", "E 471", "e-322i" in an ingredients list → ["e330", "e471", "e322i"].
    static func additiveCodes(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b[Ee][\s\-]?(\d{3,4}[a-z]{0,3})\b"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let code = "e" + text[r].lowercased()
            return seen.insert(code).inserted ? code : nil
        }
    }

    private struct Wire: Decodable {
        let name: String?
        let brand: String?
        let servingG: Double?
        let isBeverage: Bool?
        let per100g: Per100?
        let ingredients: String?
        let allergens: [String]?

        enum CodingKeys: String, CodingKey {
            case name
            case brand
            case servingG = "serving_g"
            case isBeverage = "is_beverage"
            case per100g = "per_100g"
            case ingredients, allergens
        }
    }

    private struct Per100: Decodable {
        let kcal: Double?
        let protein: Double?
        let carbs: Double?
        let sugars: Double?
        let fat: Double?
        let saturatedFat: Double?
        let fiber: Double?
        let salt: Double?

        enum CodingKeys: String, CodingKey {
            case kcal
            case protein
            case carbs
            case sugars
            case fat
            case saturatedFat = "saturated_fat"
            case fiber, salt
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
