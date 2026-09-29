//
// GenericFoodImages.swift
// Tempo
//
// A photo for foods that have none of their own — USDA results and Tempo's
// built-in table carry no image, and a wall of grey placeholder tiles is bad
// for a food search. Resolves a CC-licensed picture from Wikipedia's public
// REST summary API by the food's name, and remembers both hits and misses on
// disk so the same lookup never happens twice.
//
// FoodImageCache below is the separate byte-level cache (memory + disk) used
// to fetch and store the actual image data for ANY product photo — Open Food
// Facts or Wikipedia — so history and favourites still show a picture offline.
//

import CryptoKit
import Foundation
import os

// MARK: - GenericFoodImages

enum GenericFoodImages {
    /// Injectable so tests never touch the network.
    struct Fetcher: Sendable {
        var fetch: @Sendable (URL) async -> Data?

        static let live = Fetcher { url in
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue(GenericFoodImages.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }
    }

    static let userAgent = "Tempo/1.0 (iOS app)"

    private static let logger = Logger.nutrition
    private static let cacheFileName = "wikipedia-titles.json"
    private static let thumbnailWidth = 640

    /// A photo for `product`, resolved by its name via Wikipedia. `nil` when
    /// nothing could be found — a confirmed miss is remembered too, so the
    /// same product doesn't re-query on every visit.
    static func imageURL(
        for product: FoodProduct,
        fetcher: Fetcher = .live,
        cacheDirectory: URL? = nil
    ) async -> URL? {
        let title = titleOverrides[product.name.lowercased()] ?? deriveTitle(from: product.name)
        guard !title.isEmpty else {
            return nil
        }
        let directory = cacheDirectory ?? defaultCacheDirectory()
        var cache = readCache(directory: directory)
        if let entry = cache[title] {
            return entry.urlString.flatMap(URL.init(string:))
        }
        let resolved = await fetchFromWikipedia(title: title, fetcher: fetcher)
        cache[title] = CacheEntry(urlString: resolved?.absoluteString, checkedAt: Date())
        writeCache(cache, directory: directory)
        return resolved
    }

    /// "Greek yogurt 0%" → "Greek_yogurt" — good enough for most built-in
    /// names; `titleOverrides` fixes the ones Wikipedia titles differently.
    static func deriveTitle(from name: String) -> String {
        var cleaned = name.replacingOccurrences(of: #"\d+([.,]\d+)?\s?%"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\d+\s?/\s?\d+"#, with: "", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return ""
        }
        let words = cleaned.split(separator: " ").map(String.init)
        return words.joined(separator: "_")
    }

    /// ".../220px-Foo.jpg" → ".../640px-Foo.jpg" (Wikipedia thumbnail URLs
    /// encode the width as a path segment).
    static func rewriteThumbnailWidth(_ urlString: String, to width: Int) -> String {
        guard let range = urlString.range(of: #"/\d+px-"#, options: .regularExpression) else {
            return urlString
        }
        return urlString.replacingCharacters(in: range, with: "/\(width)px-")
    }

    /// Foods whose plain title-cased name isn't the real Wikipedia article —
    /// disambiguation pages, redirects that don't carry an image, or a very
    /// different common name.
    static let titleOverrides: [String: String] = [
        "greek yogurt": "Strained_yogurt",
        "greek yogurt 0%": "Strained_yogurt",
        "yogurt whole": "Yogurt",
        "coconut yogurt": "Yogurt",
        "frozen yogurt": "Frozen_yogurt",
        "chicken breast": "Chicken_as_food",
        "chicken thigh": "Chicken_as_food",
        "chicken drumstick": "Chicken_as_food",
        "chicken leg quarter": "Chicken_as_food",
        "chicken wing": "Chicken_as_food",
        "rotisserie chicken": "Roast_chicken",
        "eggs": "Egg_as_food",
        "egg whites": "Egg_white",
        "evoo": "Olive_oil",
        "extra virgin olive oil": "Olive_oil",
        "ground beef 80/20": "Ground_beef",
        "ground beef 85/15": "Ground_beef",
        "ground beef 90/10": "Ground_beef",
        "ground beef 93/7": "Ground_beef",
        "milk 2%": "Milk",
        "milk skim": "Skimmed_milk",
        "milk whole": "Milk",
        "milk lactose free": "Lactose-free_food",
        "tuna canned": "Canned_tuna",
        "cooked rice": "Cooked_rice",
        "cooked oats": "Oatmeal",
        "cooked pasta": "Pasta",
        "cooked polenta": "Polenta",
        "white rice": "White_rice",
        "brown rice": "Brown_rice",
        "diet coke": "Diet_Coke",
        "coke": "Coca-Cola",
        "sprite": "Sprite_(drink)",
        "protein shake": "Protein_drink",
        "meal replacement": "Meal_replacement",
        "energy bar": "Energy_bar",
        "protein bar": "Protein_bar",
        "ranch dressing": "Ranch_dressing",
        "italian dressing": "Salad_dressing",
        "cake plain": "Cake",
        "ice cream chocolate": "Ice_cream",
        "ice cream vanilla": "Ice_cream",
        "san marzano tomatoes": "San_Marzano_tomato",
        "half and half": "Half_and_half",
        "vinegar apple cider": "Apple_cider_vinegar",
        "vinegar balsamic": "Balsamic_vinegar",
        "vinegar white": "Vinegar",
    ]

    // MARK: - Private

    private struct CacheEntry: Codable {
        var urlString: String?
        var checkedAt: Date
    }

    private struct WikiSummary: Decodable {
        struct Image: Decodable {
            let source: String
        }

        let thumbnail: Image?
        let originalimage: Image?
    }

    private static func fetchFromWikipedia(title: String, fetcher: Fetcher) async -> URL? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
        else {
            return nil
        }
        guard let data = await fetcher.fetch(url) else {
            return nil
        }
        guard let summary = try? JSONDecoder().decode(WikiSummary.self, from: data),
              let raw = summary.thumbnail?.source ?? summary.originalimage?.source
        else {
            return nil
        }
        return URL(string: rewriteThumbnailWidth(raw, to: thumbnailWidth))
    }

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GenericFoodImages", isDirectory: true)
    }

    private static func readCache(directory: URL) -> [String: CacheEntry] {
        let url = directory.appendingPathComponent(cacheFileName)
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
    }

    private static func writeCache(_ cache: [String: CacheEntry], directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: directory.appendingPathComponent(cacheFileName), options: .atomic)
        } catch {
            logger.warning("[food] Wikipedia title cache write failed: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - FoodImageCache

/// Disk + memory cache for product photos so history and favourites still
/// show a picture offline. Keyed by the SHA-256 of the URL so any source
/// (Open Food Facts or a Wikipedia photo) shares the same cache.
actor FoodImageCache {
    static let shared = FoodImageCache()

    /// Injectable so tests never touch the network.
    struct Loader: Sendable {
        var load: @Sendable (URL) async -> Data?

        static let live = Loader { url in
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue(OpenFoodFactsClient.userAgent, forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }
    }

    private let memory = NSCache<NSString, NSData>()
    private let fileManager: FileManager
    private let directory: URL
    private let loader: Loader
    private let maxDiskBytes: Int
    private let logger = Logger.nutrition

    init(fileManager: FileManager = .default, directory: URL? = nil, loader: Loader = .live, maxDiskBytes: Int = 100 * 1024 * 1024) {
        self.fileManager = fileManager
        let base = directory ?? (fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory)
            .appendingPathComponent("FoodImages", isDirectory: true)
        self.directory = base
        self.loader = loader
        self.maxDiskBytes = maxDiskBytes
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    /// The image's bytes — memory, then disk, then a network fetch that's
    /// written to both. `nil` when the fetch itself fails; a failure is
    /// never remembered, so the next attempt tries again.
    func data(for url: URL) async -> Data? {
        let key = Self.cacheKey(for: url)
        if let cached = memory.object(forKey: key as NSString) {
            return cached as Data
        }
        let fileURL = directory.appendingPathComponent(key)
        if let onDisk = try? Data(contentsOf: fileURL) {
            memory.setObject(onDisk as NSData, forKey: key as NSString)
            touch(fileURL)
            return onDisk
        }
        guard let fetched = await loader.load(url) else {
            return nil
        }
        memory.setObject(fetched as NSData, forKey: key as NSString)
        do {
            try fetched.write(to: fileURL, options: .atomic)
        } catch {
            logger.warning("[food] image cache write failed: \(String(describing: error), privacy: .public)")
        }
        trimIfNeeded()
        return fetched
    }

    static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    private func touch(_ fileURL: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    /// LRU by modification date, trimmed down to `maxDiskBytes`.
    private func trimIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )
        else {
            return
        }
        let entries = files.compactMap { url -> (url: URL, size: Int, modified: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modified = values.contentModificationDate
            else {
                return nil
            }
            return (url, size, modified)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxDiskBytes else {
            return
        }
        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            guard total > maxDiskBytes else {
                break
            }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
