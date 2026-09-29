import Vapor

// MARK: - BrandCatalogRefreshing

// Seam for populating/refreshing BrandCatalogItem rows for a given brand. A
// real implementation would page through Open Food Facts' `brands_tags`
// search for that brand and upsert BrandCatalogItem rows.
//
// SCOPE CUT: no scheduled/cron refresh job and no live-calling production
// implementation are wired up here — per product priority, the requester
// said to cut the scheduled refresh job first if scope is tight. This ships
// only the plumbing (protocol + injectable seam + a no-op default) so a real
// OFF-backed implementation can be dropped in later via constructor
// injection, the same way SupplementLookupClient/InstacartClient are
// injected elsewhere in this codebase.
//
// TODO: intended lazy-on-stale-lookup trigger point — in
// BrandCatalogController.list, if the rows for the requested `brand` are
// empty or their `updated_at` is older than 7 days, call
// `refresher.refresh(brand:on:)` there (fire-and-forget or awaited,
// depending on desired latency) before/after returning the current rows.
// Deliberately NOT done yet — no implementation calls this automatically.
protocol BrandCatalogRefreshing: Sendable {
    func refresh(brand: String, on req: Request) async throws -> [BrandCatalogItem]
}

// MARK: - NullBrandCatalogRefresher

/// Default no-op conformer. Used everywhere until a real Open-Food-Facts-
/// backed implementation exists. Never makes a network call and never writes
/// to the database.
struct NullBrandCatalogRefresher: BrandCatalogRefreshing {
    func refresh(brand _: String, on _: Request) async throws -> [BrandCatalogItem] {
        []
    }
}
