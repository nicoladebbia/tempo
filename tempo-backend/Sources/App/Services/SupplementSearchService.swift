import Foundation
import Vapor

// MARK: - SupplementSearchService

//
// GET /supplements/search: three sources in parallel, each with its own timeout
// (SupplementLookupAPIClient.searchTimeoutSeconds), partial results are fine.
//   1. Tempo shared catalog (always live, never cached: it changes constantly)
//   2. NIH DSLD name search          } cached together for a day, but only when
//   3. Open Food Facts text search   } BOTH answered, so a hiccup never sticks.
// Returns nil only when every source errored (the route turns that into a 502).

enum SupplementSearchService {
    static let maxHits = 30
    static let maxCatalogHits = 10

    struct External: Codable, Sendable {
        var dsld: [SupplementSearchHit]
        var off: [SupplementSearchHit]
    }

    static func run(query: String, client: SupplementLookupClient, on req: Request) async -> [SupplementSearchHit]? {
        let timeout = SupplementLookupAPIClient.searchTimeoutSeconds
        async let catalogResult = attempt(timeout) {
            try await SupplementCatalogService.search(query: query, limit: maxCatalogHits, on: req.db)
                .map(SupplementCatalogService.searchHit)
        }

        let key = AICacheKey.supplementSearch(query: query)
        var external: External?
        var anyExternalOK = false
        if case let .fresh(cached) = (try? await AICache.shared.lookup(key: key, on: req)) as AICacheLookup<External>? ?? .miss {
            external = cached
            anyExternalOK = true
        } else {
            async let dsld = attempt(timeout) { try await client.search(query: query, on: req) }
            async let off = attempt(timeout) { try await client.searchOpenFacts(query: query, on: req) }
            let (dsldResult, offResult) = await (dsld, off)
            let dsldHits = (try? dsldResult.get()) ?? []
            let offHits = (try? offResult.get()) ?? []
            external = External(dsld: dsldHits, off: offHits)
            anyExternalOK = (try? dsldResult.get()) != nil || (try? offResult.get()) != nil
            if case .success = dsldResult, case .success = offResult {
                try? await AICache.shared.store(key: key, value: external, on: req)
            }
        }

        let catalog = try? await catalogResult.get()
        guard catalog != nil || anyExternalOK else { return nil }
        return merge(tempo: catalog ?? [], dsld: external?.dsld ?? [], off: external?.off ?? [])
    }

    /// Tempo first, then DSLD and Open Food Facts interleaved (each already in relevance
    /// order), deduped by normalized brand + name, at most 30.
    static func merge(
        tempo: [SupplementSearchHit], dsld: [SupplementSearchHit], off: [SupplementSearchHit]
    ) -> [SupplementSearchHit] {
        var seen = Set<String>()
        var out: [SupplementSearchHit] = []
        func add(_ hit: SupplementSearchHit) {
            guard out.count < maxHits, seen.insert(SupplementText.dedupeKey(brand: hit.brand, name: hit.name)).inserted else { return }
            out.append(hit)
        }
        tempo.prefix(maxCatalogHits).forEach(add)
        for index in 0 ..< max(dsld.count, off.count) {
            if index < dsld.count { add(dsld[index]) }
            if index < off.count { add(off[index]) }
        }
        return out
    }

    private static func attempt<T: Sendable>(
        _ seconds: Double, _ operation: @escaping @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return try await .success(withTimeout(seconds, operation))
        } catch {
            return .failure(error)
        }
    }
}
