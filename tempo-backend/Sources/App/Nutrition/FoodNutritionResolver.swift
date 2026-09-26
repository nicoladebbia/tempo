import Fluent
import Foundation
import SQLKit
import Vapor

// MARK: - ResolvedNutrition

/// Verified per-100g nutrition for one food, from USDA FoodData Central.
/// Feeds MacroSolver's `SolverItem.kcalPer100g` etc. When resolution fails
/// (no confident match), the caller falls back to the AI's own per-100g
/// estimate and should mark it as estimated, not verified.
struct ResolvedNutrition: Sendable, Equatable, Codable {
    let fdcId: Int
    let description: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double?
    let sugars: Double?
    /// 0...1. Lowered when the match is marginal or the food's reported
    /// energy doesn't roughly Atwater-reconcile with its macros.
    let confidence: Double
}

// MARK: - FoodNutritionResolver

//
// Resolves an AI-picked food description ("chicken breast, grilled",
// "basmati rice, cooked", "rolled oats") to verified per-100g nutrition via
// USDA FoodData Central (Foundation + SR Legacy — same generic-food data
// FoodController searches), for MacroSolver to scale grams against.
//
// - Postgres-cached (CachedFoodNutrition): hits cached indefinitely, misses
//   cached 7 days, so a name the AI keeps proposing doesn't re-hit USDA.
// - Batch resolution dedupes names and caps concurrency.
// - The USDA HTTP call is injected via USDAFoodClient, so tests never hit
//   the network — they hand the resolver canned JSON.

struct FoodNutritionResolver: Sendable {
    let usdaClient: USDAFoodClient
    /// Minimum token-overlap match score (see `matchScore`) to accept a
    /// USDA result as a confident match. Below this, resolution returns nil.
    let matchThreshold: Double
    let maxConcurrency: Int

    init(
        usdaClient: USDAFoodClient = USDAAPIClient(),
        matchThreshold: Double = 0.55,
        maxConcurrency: Int = 4
    ) {
        self.usdaClient = usdaClient
        self.matchThreshold = matchThreshold
        self.maxConcurrency = maxConcurrency
    }

    // MARK: - Single resolve

    /// Cache-through resolve for one food description. Returns nil when
    /// USDA has no confident match (cached as a miss for 7 days). Throws
    /// (without caching anything) on a USDA transport/rate-limit error — a
    /// transient 429/5xx must never get permanently mis-cached as "this food
    /// doesn't exist". Callers that want a best-effort nil instead of a
    /// throw (e.g. `resolve(_:[String],on:)` below) can `try?` this.
    func resolve(_ name: String, on req: Request) async throws -> ResolvedNutrition? {
        let normalized = Self.normalizeQuery(name)
        guard !normalized.isEmpty else { return nil }

        switch try await cacheLookup(normalized: normalized, on: req.db) {
        case let .hit(value):
            return value
        case .miss:
            return nil
        case .notCached:
            break
        }

        let raw = try await usdaClient.search(query: name, dataTypes: ["Foundation", "SR Legacy"], pageSize: 10, on: req)
        let resolved = Self.bestMatch(for: name, in: raw.foods, threshold: matchThreshold)

        // Only a genuine "no confident match" result gets cached as a miss —
        // an error above throws out of this function before we get here.
        try await storeCache(normalized: normalized, resolved: resolved, on: req.db)
        return resolved
    }

    // MARK: - Batch resolve

    /// Resolves every (deduplicated) name, at most `maxConcurrency` USDA
    /// lookups in flight at once. A name that throws (network error, etc.)
    /// resolves to nil rather than failing the whole batch.
    func resolve(_ names: [String], on req: Request) async -> [String: ResolvedNutrition?] {
        let uniqueNames = Array(Set(names))
        guard !uniqueNames.isEmpty else { return [:] }

        var results: [String: ResolvedNutrition?] = [:]
        await withTaskGroup(of: (String, ResolvedNutrition?).self) { group in
            var iterator = uniqueNames.makeIterator()

            func addNext() {
                guard let name = iterator.next() else { return }
                group.addTask {
                    let resolved = (try? await resolve(name, on: req)) ?? nil
                    return (name, resolved)
                }
            }

            for _ in 0 ..< min(maxConcurrency, uniqueNames.count) {
                addNext()
            }
            while let (name, resolved) = await group.next() {
                results[name] = resolved
                addNext()
            }
        }
        return results
    }

    // MARK: - Cache

    private enum CacheLookup {
        case hit(ResolvedNutrition)
        case miss
        case notCached
    }

    private func cacheLookup(normalized: String, on db: Database) async throws -> CacheLookup {
        guard
            let row = try await CachedFoodNutrition.query(on: db)
            .filter(\.$normalizedQuery == normalized)
            .filter(\.$expiresAt > Date())
            .first()
        else {
            return .notCached
        }
        if let value = row.toResolvedNutrition() {
            return .hit(value)
        }
        return .miss
    }

    private func storeCache(normalized: String, resolved: ResolvedNutrition?, on db: Database) async throws {
        // Hits: verified nutrition per 100g doesn't change — cache ~10 years.
        // Misses: re-try USDA after 7 days (the AI may phrase it better, or
        // USDA's index may have grown).
        let ttl: TimeInterval = resolved == nil ? 7 * 24 * 3600 : 10 * 365 * 24 * 3600
        let now = Date()
        let expiresAt = now.addingTimeInterval(ttl)

        // A real upsert (INSERT ... ON CONFLICT), not select-then-create:
        // the batch API can run several concurrent resolves for the same
        // food name, which would otherwise race the `normalized_query`
        // unique constraint (both miss the "does a row exist" check, one
        // then fails on insert).
        guard let sql = db as? SQLDatabase else {
            try await upsertViaFluent(normalized: normalized, resolved: resolved, expiresAt: expiresAt, on: db)
            return
        }
        try await sql.raw("""
        INSERT INTO food_nutrition_cache
            (id, normalized_query, is_hit, fdc_id, description, kcal, protein, carbs, fat, fiber, sugars, confidence, expires_at, created_at, updated_at)
        VALUES (
            \(bind: UUID()), \(bind: normalized), \(bind: resolved != nil), \(bind: resolved?.fdcId), \(bind: resolved?.description),
            \(bind: resolved?.kcal), \(bind: resolved?.protein), \(bind: resolved?.carbs), \(bind: resolved?.fat),
            \(bind: resolved?.fiber), \(bind: resolved?.sugars), \(bind: resolved?.confidence), \(bind: expiresAt), \(bind: now), \(bind: now)
        )
        ON CONFLICT (normalized_query) DO UPDATE SET
            is_hit = EXCLUDED.is_hit,
            fdc_id = EXCLUDED.fdc_id,
            description = EXCLUDED.description,
            kcal = EXCLUDED.kcal,
            protein = EXCLUDED.protein,
            carbs = EXCLUDED.carbs,
            fat = EXCLUDED.fat,
            fiber = EXCLUDED.fiber,
            sugars = EXCLUDED.sugars,
            confidence = EXCLUDED.confidence,
            expires_at = EXCLUDED.expires_at,
            updated_at = EXCLUDED.updated_at
        """).run()
    }

    /// Fallback for a non-SQL Fluent driver (not expected in this app, but
    /// keeps the resolver from hard-depending on Postgres-specific SQL).
    private func upsertViaFluent(normalized: String, resolved: ResolvedNutrition?, expiresAt: Date, on db: Database) async throws {
        if let existing = try await CachedFoodNutrition.query(on: db)
            .filter(\.$normalizedQuery == normalized)
            .first()
        {
            existing.apply(resolved: resolved)
            existing.expiresAt = expiresAt
            try await existing.save(on: db)
        } else {
            let row = CachedFoodNutrition(normalizedQuery: normalized, resolved: resolved, expiresAt: expiresAt)
            try await row.create(on: db)
        }
    }

    // MARK: - Query normalization

    static func normalizeQuery(_ text: String) -> String {
        tokenize(text).joined(separator: " ")
    }

    private static let stopWords: Set<String> = ["a", "an", "the", "with", "and", "of", "in", "some"]

    private static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = String(lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        return cleaned.split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    // MARK: - Match selection

    /// Picks the best-scoring USDA result for `query`, or nil when nothing
    /// clears `threshold`. Reuses FoodDTO's nutrient-extraction so a food
    /// missing core macros (kcal/protein/carbs/fat) is skipped automatically.
    static func bestMatch(for query: String, in foods: [USDASearchRawResponse.Food], threshold: Double) -> ResolvedNutrition? {
        let queryTokens = Set(tokenize(query))
        guard !queryTokens.isEmpty else { return nil }

        var best: (dto: FoodDTO, score: Double)?
        for food in foods {
            guard let dto = FoodDTO(usda: food) else { continue }
            let candidateTokens = Set(tokenize(food.description))
            let score = matchScore(queryTokens: queryTokens, candidateTokens: candidateTokens, dataType: food.dataType)
            guard score >= threshold else { continue }
            if best == nil || score > best!.score {
                best = (dto, score)
            }
        }
        guard let match = best else { return nil }

        let (consistent, _) = atwaterConsistency(kcal: match.dto.kcal, protein: match.dto.protein, carbs: match.dto.carbs, fat: match.dto.fat)
        var confidence = min(max(match.score, 0), 1)
        if !consistent {
            confidence *= 0.6
        }

        return ResolvedNutrition(
            fdcId: match.dto.fdcID,
            description: match.dto.name,
            kcal: match.dto.kcal,
            protein: match.dto.protein,
            carbs: match.dto.carbs,
            fat: match.dto.fat,
            fiber: match.dto.fiber,
            sugars: match.dto.sugars,
            confidence: confidence
        )
    }

    /// 4/4/9 Atwater check: does reported kcal roughly reconcile with
    /// protein*4 + carbs*4 + fat*9, within ~15%?
    static func atwaterConsistency(kcal: Double, protein: Double, carbs: Double, fat: Double) -> (consistent: Bool, atwaterKcal: Double) {
        let atwaterKcal = protein * 4 + carbs * 4 + fat * 9
        guard kcal > 1 else { return (atwaterKcal <= 1, atwaterKcal) }
        let consistent = abs(kcal - atwaterKcal) <= 0.15 * kcal
        return (consistent, atwaterKcal)
    }

    private static let cookedWords: Set<String> = [
        "cooked", "grilled", "roasted", "baked", "boiled", "steamed", "broiled", "poached", "fried", "braised",
    ]

    /// Simple token-overlap score: fraction of query words found in the
    /// candidate description, penalized for unrelated extra words, boosted
    /// when the query and candidate agree on cooked-vs-raw, and lightly
    /// favoring Foundation/SR Legacy over other data types.
    static func matchScore(queryTokens: Set<String>, candidateTokens: Set<String>, dataType: String?) -> Double {
        guard !queryTokens.isEmpty else { return 0 }

        let overlap = queryTokens.intersection(candidateTokens).count
        var score = Double(overlap) / Double(queryTokens.count)

        let extra = candidateTokens.subtracting(queryTokens).count
        score -= Double(extra) * 0.02

        let queryHasCooked = !queryTokens.isDisjoint(with: cookedWords)
        let candidateHasCooked = !candidateTokens.isDisjoint(with: cookedWords)
        let queryHasRaw = queryTokens.contains("raw")
        let candidateHasRaw = candidateTokens.contains("raw")

        if queryHasCooked, candidateHasCooked {
            score += 0.15
        }
        if queryHasCooked, candidateHasRaw, !candidateHasCooked {
            score -= 0.15
        }
        if queryHasRaw, candidateHasRaw {
            score += 0.15
        }
        if queryHasRaw, candidateHasCooked, !candidateHasRaw {
            score -= 0.15
        }

        switch dataType {
        case "Foundation": score += 0.03
        case "SR Legacy": score += 0.01
        default: break
        }

        return score
    }
}
