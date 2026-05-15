import Foundation
import Vapor

// MARK: - AIFeatureRunner
//
// Per AI_INTELLIGENCE_ENGINE.md §3 + INTELLIGENCE_REMEDIATION_PLAN.md §7.
//
// Common runner for every AI feature. Wraps the four cross-cutting concerns
// every §3 feature shares so individual services only define:
//   - the prompt
//   - the parser/validator
//   - the fallback
//
// Cross-cutting concerns handled here:
//   1. Cache lookup + store (AICache)
//   2. Circuit breaker check + record (InsightService.circuitBreaker for now)
//   3. Pre-flight budget gate + post-call recordSpend (AIBudgetTracker)
//   4. Retry + structured-error mapping
//
// Each new feature drops in by calling AIFeatureRunner.run(...) instead of
// re-implementing the gate/cache/breaker dance.

struct AIFeatureSpec<Output: Codable & Sendable>: Sendable {
    let model: String        // AIConfig.haikuModel / sonnetModel / opusModel
    let maxTokens: Int
    let temperature: Double
    let timeout: TimeInterval
    let estimatedInputTokens: Int   // for budget pre-flight
    let cacheKey: AICacheKey?       // nil = no caching
}

enum AIFeatureRunner {

    /// Run an AI feature end-to-end. Returns the parsed Output (from cache
    /// or fresh Claude call) plus a `fromCache: Bool` flag.
    ///
    /// `buildPrompts`: closure returning (system, user) prompt strings.
    /// `parse`: closure that turns Claude's text response into Output, or
    ///          throws if the response is malformed (caller retries once).
    /// `fallback`: synchronous fallback used when cache misses AND Claude
    ///             fails (circuit open, budget exhausted, network error,
    ///             malformed JSON after retry). Keeps the user moving.
    static func run<Output: Codable & Sendable>(
        spec: AIFeatureSpec<Output>,
        on req: Request,
        bypassCache: Bool = false,
        useSWR: Bool = false,
        buildPrompts: @escaping @Sendable () async throws -> (system: String, user: String),
        parse: @escaping @Sendable (String) throws -> Output,
        fallback: @escaping @Sendable () -> Output
    ) async throws -> (value: Output, fromCache: Bool) {

        // 1a. Stale-while-revalidate fast path. When the caller opts in and
        //     this feature has a cache key, delegate the lookup-vs-store
        //     dance to AICache.withSWR. Stale hits return the cached value
        //     immediately and trigger a background refresh; misses fall
        //     through to the synchronous compute path. Per
        //     LAUNCH_PUNCH_LIST.md §3.6.
        if useSWR, let key = spec.cacheKey, !bypassCache {
            return try await AICache.shared.withSWR(key: key, on: req) {
                let result = try await Self.compute(
                    spec: spec,
                    on: req,
                    buildPrompts: buildPrompts,
                    parse: parse,
                    fallback: fallback
                )
                return result.value
            }
        }

        // 1. Cache lookup (sync path)
        if !bypassCache, let key = spec.cacheKey,
           case let .fresh(hit) = try await AICache.shared.lookup(key: key, on: req) as AICacheLookup<Output>
        {
            req.logger.info("[ai_runner:\(key.feature)] HIT key=\(key.value)")
            return (hit, true)
        }

        let result = try await compute(
            spec: spec,
            on: req,
            buildPrompts: buildPrompts,
            parse: parse,
            fallback: fallback
        )
        // Cache the fresh result for the sync path. The SWR path stores
        // its own copy via withSWR — when this method is called from
        // inside the withSWR generator we skip the cache key (handled
        // above), so we never end up double-storing.
        if let key = spec.cacheKey {
            try? await AICache.shared.store(key: key, value: result.value, on: req)
        }
        return result
    }

    /// The cache-less compute path: circuit breaker → budget → prompts →
    /// Claude → parse → optional malformed-JSON retry. Returns the parsed
    /// Output paired with `fromCache: false`. Used by `run` directly and
    /// by the SWR fast-path (where caching is handled by `AICache.withSWR`).
    private static func compute<Output: Codable & Sendable>(
        spec: AIFeatureSpec<Output>,
        on req: Request,
        buildPrompts: () async throws -> (system: String, user: String),
        parse: (String) throws -> Output,
        fallback: () -> Output
    ) async throws -> (value: Output, fromCache: Bool) {

        // 2. Circuit breaker
        let breaker = await InsightService.shared.circuitBreakerState(for: spec.model)
        if breaker == .open {
            req.logger.warning("[ai_runner] circuit OPEN model=\(spec.model) — using fallback")
            return (fallback(), false)
        }

        // 3. Pre-flight budget gate
        let estimate = AIBudgetTracker.shared.estimateCostCents(
            model: spec.model,
            estimatedInputTokens: spec.estimatedInputTokens,
            maxOutputTokens: spec.maxTokens
        )
        guard await AIBudgetTracker.shared.canMakeCall(estimatedCostCents: estimate, on: req) else {
            req.logger.warning("[ai_runner] budget exhausted model=\(spec.model) — using fallback")
            return (fallback(), false)
        }

        // 4. Build prompts (caller may throw if missing inputs)
        let prompts: (system: String, user: String)
        do {
            prompts = try await buildPrompts()
        } catch {
            req.logger.error("[ai_runner] prompt-build failed: \(error.localizedDescription) — using fallback")
            return (fallback(), false)
        }

        // 5. Call Claude (one attempt + one retry on malformed-JSON per spec §2.3)
        do {
            let response = try await InsightService.shared.callClaudeRaw(
                model: spec.model,
                systemPrompt: prompts.system,
                userPrompt: prompts.user,
                temperature: spec.temperature,
                maxTokens: spec.maxTokens,
                timeout: spec.timeout,
                on: req
            )
            // 6. Parse
            let parsed: Output
            do {
                parsed = try parse(response.content)
            } catch {
                req.logger.warning("[ai_runner] malformed response — retrying with stricter prompt")
                let strictUser = prompts.user + "\n\nCRITICAL: Return ONLY valid JSON. No markdown, no code blocks, no explanatory text. Start with { and end with }."
                let retry = try await InsightService.shared.callClaudeRaw(
                    model: spec.model,
                    systemPrompt: prompts.system,
                    userPrompt: strictUser,
                    temperature: spec.temperature,
                    maxTokens: spec.maxTokens,
                    timeout: spec.timeout,
                    on: req
                )
                parsed = try parse(retry.content)
            }

            return (parsed, false)

        } catch {
            req.logger.error("[ai_runner] Claude call failed model=\(spec.model) err=\(error.localizedDescription) — using fallback")
            return (fallback(), false)
        }
    }
}

// Helper methods `circuitBreakerState(for:)` and `callClaudeRaw(...)` live
// in InsightService.swift itself (Swift extension visibility rules prevent
// them from being defined here while referencing private members).
