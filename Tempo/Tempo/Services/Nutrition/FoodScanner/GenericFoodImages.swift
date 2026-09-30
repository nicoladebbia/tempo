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
    /// A fetch attempt's outcome, distinguishing a *definitive* miss (safe to
    /// remember forever) from a transient one (must be retried, never cached
    /// as permanent) — collapsing both into a plain `nil` was the bug behind
    /// built-in "Banana" permanently showing no photo after a single 429 or
    /// timeout: that failure got written to disk as "no image exists" and
    /// every later visit trusted the stale miss instead of asking again.
    enum FetchOutcome: Equatable, Sendable {
        /// Got a page (200) with no usable image, or a real 404 — this title
        /// genuinely has no photo.
        case definitiveMiss
        /// Network/rate-limit/decoding trouble — try again next time.
        case transientFailure
        case success(Data)
    }

    /// Injectable so tests never touch the network.
    struct Fetcher: Sendable {
        var fetch: @Sendable (URL) async -> FetchOutcome

        static let live = Fetcher { url in
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue(GenericFoodImages.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch status {
                case 200:
                    return .success(data)
                case 404:
                    return .definitiveMiss
                default:
                    // 429 (rate limited), 5xx, or anything unexpected — the
                    // page may well exist, Wikipedia just didn't answer.
                    return .transientFailure
                }
            } catch {
                return .transientFailure
            }
        }
    }

    static let userAgent = "Tempo/1.0 (iOS app)"

    private static let logger = Logger.nutrition
    private static let cacheFileName = "wikipedia-titles-v2.json"
    /// Wikimedia only serves thumbnails at its standard steps (…330, 500,
    /// 960…); any other width, e.g. 640, is a 400 and the photo never loads.
    static let thumbnailWidth = 500

    /// A photo for `product`, resolved by its name via Wikipedia. `nil` when
    /// nothing could be found — a confirmed miss is remembered too, so the
    /// same product doesn't re-query on every visit.
    static func imageURL(
        for product: FoodProduct,
        fetcher: Fetcher = .live,
        cacheDirectory: URL? = nil,
        retryAfter: TimeInterval = Resolver.retryAfter
    ) async -> URL? {
        let title = titleOverrides[product.name.lowercased()] ?? deriveTitle(from: product.name)
        guard !title.isEmpty else {
            return nil
        }
        let directory = cacheDirectory ?? defaultCacheDirectory()
        return await Resolver.shared.resolve(title: title, directory: directory, fetcher: fetcher, retryAfter: retryAfter)
    }

    /// Serializes the read → fetch → write cycle so rows rendering together
    /// share one request per title and never overwrite each other's entries.
    private actor Resolver {
        static let shared = Resolver()

        /// How long a *transient* failure (429/timeout/5xx) is trusted before
        /// the next visit is allowed to ask Wikipedia again. A *definitive*
        /// miss (200 with no image, or a real 404) has no expiry — that
        /// title just has no photo.
        static let retryAfter: TimeInterval = 30 * 60

        private var inFlight: [String: Task<URL?, Never>] = [:]

        func resolve(title: String, directory: URL, fetcher: Fetcher, retryAfter: TimeInterval) async -> URL? {
            let key = directory.path + "|" + title
            if let pending = inFlight[key] {
                return await pending.value
            }
            if let entry = GenericFoodImages.readCache(directory: directory)[title] {
                let transientAndStale = !entry.isDefinitive && Date().timeIntervalSince(entry.checkedAt) > retryAfter
                if !transientAndStale {
                    return entry.urlString.flatMap(URL.init(string:))
                }
            }
            let task = Task { () -> URL? in
                let outcome = await fetcher.fetch(GenericFoodImages.wikipediaURL(title: title))
                return GenericFoodImages.handle(outcome, title: title, directory: directory)
            }
            inFlight[key] = task
            let resolved = await task.value
            inFlight[key] = nil
            return resolved
        }
    }

    /// Writes the outcome to the shared cache (definitive vs. transient) and
    /// returns the resolved URL, if any.
    fileprivate static func handle(_ outcome: FetchOutcome, title: String, directory: URL) -> URL? {
        let url: URL?
        let isDefinitive: Bool
        switch outcome {
        case .definitiveMiss:
            url = nil
            isDefinitive = true
        case .transientFailure:
            url = nil
            isDefinitive = false
        case let .success(data):
            switch parseImageURL(from: data) {
            case let .image(found):
                url = found
                isDefinitive = true
            case .noImage:
                // A real Wikipedia page, just no thumbnail — genuinely has no photo.
                url = nil
                isDefinitive = true
            case .decodeFailed:
                // A 200 with a body we couldn't parse is Wikipedia's shape
                // changing (or a transient CDN error page), not "no photo".
                url = nil
                isDefinitive = false
            }
        }
        // Re-read after the await: other titles may have landed meanwhile.
        var cache = readCache(directory: directory)
        cache[title] = CacheEntry(urlString: url?.absoluteString, checkedAt: Date(), isDefinitive: isDefinitive)
        writeCache(cache, directory: directory)
        return url
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

    /// ".../220px-Foo.jpg" → ".../500px-Foo.jpg" (Wikipedia thumbnail URLs
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

    fileprivate struct CacheEntry: Codable {
        var urlString: String?
        var checkedAt: Date
        /// `true` for a genuine "this title has no photo" (200 with no
        /// thumbnail, or a real 404) — trusted forever. `false` for a
        /// network/rate-limit/decode hiccup — retried after `Resolver.retryAfter`.
        var isDefinitive: Bool

        init(urlString: String?, checkedAt: Date, isDefinitive: Bool = true) {
            self.urlString = urlString
            self.checkedAt = checkedAt
            self.isDefinitive = isDefinitive
        }

        private enum CodingKeys: String, CodingKey {
            case urlString
            case checkedAt
            case isDefinitive
        }

        /// Swift's synthesized `Decodable` does NOT fall back to a stored
        /// property's default value when the JSON key is simply absent — it
        /// throws `keyNotFound`. `readCache` decodes the whole cache
        /// dictionary in one shot, so a single old-format entry (written
        /// before this field existed) would otherwise fail the entire file
        /// and silently wipe every cached hit and miss on first launch after
        /// this update. This custom init is what actually makes missing
        /// `isDefinitive` default to `true`, as already-settled entries.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
            checkedAt = try container.decode(Date.self, forKey: .checkedAt)
            isDefinitive = try container.decodeIfPresent(Bool.self, forKey: .isDefinitive) ?? true
        }
    }

    private struct WikiSummary: Decodable {
        struct Image: Decodable {
            let source: String
            let width: Int?
        }

        let thumbnail: Image?
        let originalimage: Image?
    }

    fileprivate enum ParseResult {
        case image(URL)
        /// Decoded fine, genuinely no thumbnail on the page.
        case noImage
        /// Not decodable as a Wikipedia summary at all.
        case decodeFailed
    }

    fileprivate static func wikipediaURL(title: String) -> URL {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        // Falls back to a URL that will 404 rather than crash if `title`
        // somehow can't be encoded — vanishingly rare (only empty titles,
        // already guarded by the caller).
        return URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
            ?? URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/_")!
    }

    fileprivate static func parseImageURL(from data: Data) -> ParseResult {
        guard let summary = try? JSONDecoder().decode(WikiSummary.self, from: data) else {
            return .decodeFailed
        }
        let raw: String
        if let original = summary.originalimage, let width = original.width, width <= thumbnailWidth {
            // Asking for a thumbnail wider than the original is also a 400.
            raw = original.source
        } else if let thumbnail = summary.thumbnail?.source {
            raw = rewriteThumbnailWidth(thumbnail, to: thumbnailWidth)
        } else if let original = summary.originalimage?.source {
            raw = original
        } else {
            return .noImage
        }
        guard let url = URL(string: raw) else {
            return .noImage
        }
        return .image(url)
    }

    private static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GenericFoodImages", isDirectory: true)
    }

    fileprivate static func readCache(directory: URL) -> [String: CacheEntry] {
        let url = directory.appendingPathComponent(cacheFileName)
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: CacheEntry].self, from: data)) ?? [:]
    }

    fileprivate static func writeCache(_ cache: [String: CacheEntry], directory: URL) {
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
