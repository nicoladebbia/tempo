//
// SupplementLabelReader.swift
// Tempo
//
// The "can't find it" safety net for the supplement scanner: photograph the
// Supplement Facts panel and Claude Haiku Vision (same Pro-gated nutrition AI
// proxy the food label reader uses) turns it into a product the user confirms
// and edits before it lands on the shelf. Nothing is saved from here.
//

import Foundation

enum SupplementLabelReader {
    static let systemPrompt = """
    You read dietary supplement packaging photos (any language, often English or \
    Italian) and return ONLY valid JSON, no prose, no code fences. Shape:
    {"name":"<product name or null>","brand":"<brand or null>",\
    "kind":"<protein|creatine|omega3|multivitamin|vitamin|preworkout|electrolytes|other>",\
    "serving":"<one serving, e.g. '1 scoop (30 g)', '2 softgels', or null>",\
    "servings_per_container":<number or null>,\
    "per_serving":{"kcal":<n|null>,"protein":<n|null>,"carbs":<n|null>,"fat":<n|null>},\
    "ingredients":["<active ingredient with amount, e.g. 'Vitamin D3 25 mcg'>", ...]}
    Everything is PER ONE SERVING as printed on the Supplement Facts panel. \
    Protein, carbs and fat in grams. Use null for anything you can't read. \
    Never guess a number that isn't printed.
    """

    @MainActor
    static func read(imageJPEG: Data, upc: String?, apiClient: APIClient) async throws -> SupplementLookupDTO {
        let body = NutritionProxyVisionRequest(
            model: "haiku",
            system: systemPrompt,
            userMessage: "Read this supplement's label.",
            imageMediaType: "image/jpeg",
            imageBase64: PhotoAnalysisService.downsampledBase64(imageJPEG),
            maxTokens: 900,
            temperature: 0,
            caller: "supplement_label_reader"
        )
        let response: NutritionProxyTextResponse = try await apiClient.request(.nutritionProxyVision(), body: body)
        return try parse(response.text, upc: upc)
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case unreadable

        var errorDescription: String? {
            "Couldn't read that label. Try a sharper, closer photo of the Supplement Facts — or type it in."
        }
    }

    static func parse(_ raw: String, upc: String?) throws -> SupplementLookupDTO {
        guard let json = TrainerProgramParser.extractJSON(from: raw),
              let data = json.data(using: .utf8),
              let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let name = wire.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else {
            throw ParseError.unreadable
        }
        let per = wire.perServing
        return SupplementLookupDTO(
            upc: upc ?? "",
            brand: wire.brand?.nilIfBlank,
            name: name,
            kind: SupplementKind(rawValue: wire.kind ?? "")?.rawValue ?? SupplementKind.other.rawValue,
            dosePerServing: wire.serving?.nilIfBlank,
            servingsPerContainer: wire.servingsPerContainer.flatMap { $0 > 0 ? $0 : nil },
            proteinGramsPerServing: per?.protein.flatMap { $0 > 0 ? $0 : nil },
            caloriesPerServing: per?.kcal.flatMap { $0 > 0 ? $0 : nil },
            carbsGramsPerServing: per?.carbs.flatMap { $0 > 0 ? $0 : nil },
            fatGramsPerServing: per?.fat.flatMap { $0 > 0 ? $0 : nil },
            certifications: [],
            source: "label",
            ingredients: wire.ingredients?.compactMap { $0.nilIfBlank }.prefix(30).map { $0 }
        )
    }

    private struct Wire: Decodable {
        let name: String?
        let brand: String?
        let kind: String?
        let serving: String?
        let servingsPerContainer: Double?
        let perServing: Per?
        let ingredients: [String]?

        enum CodingKeys: String, CodingKey {
            case name, brand, kind, serving, ingredients
            case servingsPerContainer = "servings_per_container"
            case perServing = "per_serving"
        }
    }

    private struct Per: Decodable {
        let kcal: Double?
        let protein: Double?
        let carbs: Double?
        let fat: Double?
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
