//
// OpenFoodFactsClient.swift
// Tempo
//
// Open Food Facts (world.openfoodfacts.org, ODbL) — the open database Yuka
// was built on. Called straight from the phone: OFF rate-limits per IP
// (product reads 15/min, search 10/min), so each user gets their own budget
// and our server never becomes the bottleneck.
//
//   product(barcode:)   GET /api/v2/product/{code}         (barcode scan)
//   search(_:)          search-a-licious full-text          (food search)
//   alternatives(for:)  search-a-licious by category        ("better options")
//

import Foundation
import os

// MARK: - FoodProductProviding

protocol FoodProductProviding: Sendable {
    func product(barcode: String) async throws -> FoodProduct?
    func search(_ query: String, limit: Int) async throws -> [FoodProduct]
    /// Better-graded products from the product's most specific category.
    func alternatives(for product: FoodProduct, limit: Int) async throws -> [FoodProduct]
}

// MARK: - FoodLookupError

enum FoodLookupError: Error, Equatable, LocalizedError {
    case rateLimited
    case offline
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited: "Too many lookups in a minute. Wait a moment and try again."
        case .offline: "You're offline. Connect to look up products."
        case let .server(code): "The food database didn't answer (\(code)). Try again."
        }
    }
}

// MARK: - OpenFoodFactsClient

struct OpenFoodFactsClient: FoodProductProviding {
    static let productBase = URL(string: "https://world.openfoodfacts.org/api/v2/product/")!
    static let searchBase = URL(string: "https://search.openfoodfacts.org/search")!

    static let fields = [
        "code", "product_name", "product_name_en", "product_name_it", "brands", "quantity",
        "serving_size", "serving_quantity", "nutriments", "nutriscore_grade", "nutriscore_score",
        "nova_group", "additives_tags", "allergens_tags", "labels_tags", "categories_tags",
        "categories_hierarchy", "ingredients_analysis_tags", "ingredients_text", "ingredients_text_it",
        "ingredients_text_en", "image_front_url", "image_front_small_url", "countries_tags",
    ].joined(separator: ",")

    /// OFF asks every app to identify itself.
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Tempo/\(version) (iOS; https://tempo.app/support)"
    }

    let session: URLSession
    /// Two-letter language for names ("it", "en").
    let language: String
    /// Country tag for alternatives ("en:italy"); nil = worldwide.
    let countryTag: String?

    private let logger = Logger.nutrition

    init(session: URLSession = .shared, locale: Locale = .current) {
        self.session = session
        language = locale.language.languageCode?.identifier ?? "en"
        countryTag = locale.region.flatMap { Self.countryTags[$0.identifier] }
    }

    func product(barcode: String) async throws -> FoodProduct? {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty else {
            return nil
        }
        var components = URLComponents(url: Self.productBase.appendingPathComponent(code), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        let data = try await get(components.url!, allow404: true)
        guard let data else {
            return nil
        }
        let envelope = try JSONDecoder().decode(OFFProductEnvelope.self, from: data)
        guard envelope.status == 1, let product = envelope.product?.toProduct(fallbackCode: code, language: language) else {
            return nil
        }
        // Some unknown barcodes come back as empty stubs: treat them as not found
        // so the user can add the product.
        guard product.per100g.kcal != nil || !product.name.isEmpty else {
            return nil
        }
        return product
    }

    func search(_ query: String, limit: Int = 20) async throws -> [FoodProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return []
        }
        return try await searchHits(query: trimmed, sortBy: nil, limit: limit)
    }

    func alternatives(for product: FoodProduct, limit: Int = 6) async throws -> [FoodProduct] {
        guard let category = product.categories.last else {
            return []
        }
        var clauses = ["categories_tags:\"en:\(category)\"", "nutrition_grades:(a OR b)"]
        if let countryTag {
            clauses.append("countries_tags:\"\(countryTag)\"")
        }
        let hits = try await searchHits(query: clauses.joined(separator: " AND "), sortBy: "-unique_scans_n", limit: limit + 4)
        return hits.filter { $0.barcode != product.barcode && $0.per100g.hasCoreMacros }
    }

    // MARK: - Private

    private func searchHits(query: String, sortBy: String?, limit: Int) async throws -> [FoodProduct] {
        var components = URLComponents(url: Self.searchBase, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "langs", value: language == "en" ? "en" : "\(language),en"),
            URLQueryItem(name: "fields", value: Self.fields),
        ]
        if let sortBy {
            items.append(URLQueryItem(name: "sort_by", value: sortBy))
        }
        components.queryItems = items
        guard let data = try await get(components.url!, allow404: false) else {
            return []
        }
        let response = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return response.hits.compactMap { $0.toProduct(fallbackCode: nil, language: language) }
    }

    private func get(_ url: URL, allow404: Bool) async throws -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw FoodLookupError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200 ..< 300:
            return data
        case 404 where allow404:
            return nil
        case 429:
            throw FoodLookupError.rateLimited
        default:
            logger.warning("[food] OFF \(url.path, privacy: .public) → \(status)")
            throw FoodLookupError.server(status)
        }
    }

    /// Region → OFF country tag, for the markets Tempo ships in first.
    static let countryTags: [String: String] = [
        "IT": "en:italy", "FR": "en:france", "DE": "en:germany", "ES": "en:spain", "GB": "en:united-kingdom",
        "US": "en:united-states", "CH": "en:switzerland", "AT": "en:austria", "BE": "en:belgium",
        "NL": "en:netherlands", "PT": "en:portugal", "IE": "en:ireland", "CA": "en:canada", "AU": "en:australia",
    ]
}

// MARK: - OFFProductEnvelope

struct OFFProductEnvelope: Decodable {
    let status: Int?
    let product: OFFRawProduct?
}

// MARK: - OFFSearchResponse

struct OFFSearchResponse: Decodable {
    let hits: [OFFRawProduct]
}

// MARK: - OFFRawProduct

/// Tolerant decoding: OFF mixes strings/numbers/arrays for the same field
/// across endpoints (e.g. `brands` is a string on /product, an array in search).
struct OFFRawProduct: Decodable {
    let code: String?
    let names: [String: String]
    let brands: [String]
    let quantity: String?
    let servingSize: String?
    let servingQuantity: Double?
    let nutriments: [String: Double]
    let nutriscoreGrade: String?
    let nutriscoreScore: Int?
    let novaGroup: Int?
    let additives: [String]
    let allergens: [String]
    let labels: [String]
    let categories: [String]
    let ingredientsAnalysis: [String]
    let ingredientsText: [String: String]
    let imageFront: String?
    let imageFrontSmall: String?

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? {
            nil
        }

        init(_ string: String) {
            stringValue = string
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func string(_ key: String) -> String? {
            if let value = try? c.decodeIfPresent(String.self, forKey: Key(key)) {
                return value.isEmpty ? nil : value
            }
            if let number = try? c.decodeIfPresent(Double.self, forKey: Key(key)) {
                return String(number)
            }
            return nil
        }
        func double(_ key: String) -> Double? {
            if let number = try? c.decodeIfPresent(Double.self, forKey: Key(key)) {
                return number
            }
            return (try? c.decodeIfPresent(String.self, forKey: Key(key))).flatMap { $0.flatMap { Double($0.replacingOccurrences(
                of: ",",
                with: "."
            )) } }
        }
        func tags(_ key: String) -> [String] {
            let raw: [String] = if let array = try? c.decodeIfPresent([String].self, forKey: Key(key)) {
                array
            } else if let joined = try? c.decodeIfPresent(String.self, forKey: Key(key)) {
                joined.split(separator: ",").map(String.init)
            } else {
                []
            }
            return raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        code = string("code")
        var names: [String: String] = [:]
        for (key, lang) in [("product_name", ""), ("product_name_en", "en"), ("product_name_it", "it")] {
            if let value = string(key) {
                names[lang] = value
            }
        }
        self.names = names
        brands = tags("brands")
        quantity = string("quantity")
        servingSize = string("serving_size")
        servingQuantity = double("serving_quantity")
        nutriments = (try? c.decodeIfPresent([String: FlexibleDouble].self, forKey: Key("nutriments")))??
            .compactMapValues(\.value) ?? [:]
        nutriscoreGrade = string("nutriscore_grade")
        nutriscoreScore = double("nutriscore_score").map { Int($0) }
        novaGroup = double("nova_group").map { Int($0) }
        additives = tags("additives_tags")
        allergens = tags("allergens_tags")
        labels = tags("labels_tags")
        let hierarchy = tags("categories_hierarchy")
        categories = hierarchy.isEmpty ? tags("categories_tags") : hierarchy
        ingredientsAnalysis = tags("ingredients_analysis_tags")
        var ingredients: [String: String] = [:]
        for (key, lang) in [("ingredients_text", ""), ("ingredients_text_en", "en"), ("ingredients_text_it", "it")] {
            if let value = string(key) {
                ingredients[lang] = value
            }
        }
        ingredientsText = ingredients
        imageFront = string("image_front_url")
        imageFrontSmall = string("image_front_small_url")
    }

    /// "400 g e" / "400 g ℮" → "400 g" (the EU estimated-quantity mark).
    static func cleanQuantity(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        for mark in [" ℮", " e"] where text.hasSuffix(mark) {
            text = String(text.dropLast(mark.count))
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    func toProduct(fallbackCode: String?, language: String) -> FoodProduct? {
        guard let barcode = code ?? fallbackCode,
              let name = names[language] ?? names[""] ?? names["en"] ?? names.values.first
        else {
            return nil
        }
        func stripped(_ tags: [String]) -> [String] {
            tags.map { $0.split(separator: ":").last.map(String.init) ?? $0 }
        }
        let grade = nutriscoreGrade?.lowercased()
        let categoryTags = stripped(categories)
        let per100g = FoodProduct.Nutrients(
            kcal: nutriments["energy-kcal_100g"] ?? nutriments["energy_100g"].map { $0 / 4.184 },
            protein: nutriments["proteins_100g"],
            carbs: nutriments["carbohydrates_100g"],
            sugars: nutriments["sugars_100g"],
            fat: nutriments["fat_100g"],
            saturatedFat: nutriments["saturated-fat_100g"],
            fiber: nutriments["fiber_100g"],
            salt: nutriments["salt_100g"] ?? nutriments["sodium_100g"].map { $0 * 2.5 }
        )
        let servingGrams = servingQuantity.flatMap { $0 > 0 ? $0 : nil } ?? FoodProduct.grams(fromLabel: servingSize)
        return FoodProduct(
            id: barcode,
            barcode: barcode,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brands.first,
            source: .openFoodFacts,
            quantityLabel: quantity.map(Self.cleanQuantity),
            servingLabel: servingSize,
            servingGrams: servingGrams,
            isBeverage: categoryTags.contains("beverages") && !categoryTags.contains("dairies"),
            per100g: per100g,
            nutriScoreGrade: FoodProduct.validGrade(grade),
            nutriScorePoints: FoodProduct.validGrade(grade) == nil ? nil : nutriscoreScore,
            novaGroup: novaGroup.flatMap { (1 ... 4).contains($0) ? $0 : nil },
            additives: additives.map { FoodAdditiveTable.normalize($0) },
            allergens: stripped(allergens),
            labels: stripped(labels),
            categories: categoryTags,
            ingredientsAnalysis: stripped(ingredientsAnalysis),
            ingredientsText: ingredientsText[language] ?? ingredientsText[""] ?? ingredientsText["en"],
            imageURL: imageFront.flatMap(URL.init(string:)),
            imageSmallURL: imageFrontSmall.flatMap(URL.init(string:))
        )
    }
}

// MARK: - FlexibleDouble

/// A nutriment value that may arrive as a number or a numeric string.
private struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let number = try? c.decode(Double.self) {
            value = number
        } else if let string = try? c.decode(String.self) {
            value = Double(string)
        } else {
            value = nil
        }
    }
}

extension FoodProduct {
    /// "a"…"e" only — OFF also sends "unknown" / "not-applicable".
    static func validGrade(_ grade: String?) -> String? {
        guard let grade, NutriScore.grades.contains(grade) else {
            return nil
        }
        return grade
    }
}
