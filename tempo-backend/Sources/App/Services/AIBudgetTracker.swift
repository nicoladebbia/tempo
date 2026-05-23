import Fluent
import SQLKit
import Vapor

// MARK: - AIBudgetTracker
//
// Per AI_INTELLIGENCE_ENGINE.md §5.4 + INTELLIGENCE_REMEDIATION_PLAN.md §5.
//
// Hard ceiling on Anthropic spend per calendar month. Replaces the in-memory
// stub previously inside InsightService. Persists to PostgreSQL so:
//   - Spend tracking survives process restarts (no surprise bills after redeploy).
//   - Multiple Vapor replicas share the same counter.
//   - Threshold action level is durable (warnings don't re-fire per restart).
//
// Pre-flight gating: callers query canMakeCall(estimatedCostCents:) BEFORE
// hitting Claude. If the worst-case estimate would push spend over the cap,
// the call is rejected and the caller falls back to rule-based output.
//
// Cost model is in microdollars (1µ = $0.000001) for precision; conversion
// to cents happens only at persistence time. Reference per million tokens:
//   Haiku  : $1.00 in / $5.00  out  (=>  1µ in / 5µ  out per token)
//   Sonnet : $3.00 in / $15.00 out  (=>  3µ in / 15µ out per token)
//   Opus   : $15.0 in / $75.00 out  (=> 15µ in / 75µ out per token)

actor AIBudgetTracker {
    static let shared = AIBudgetTracker()

    // ── Threshold ladder ──────────────────────────
    // Per AI_INTELLIGENCE_ENGINE.md §5.4 alert thresholds.
    // The "applied" level is persisted so the same warning isn't logged on
    // every call once a level is crossed.

    enum ThrottleLevel: Int, Sendable {
        case none = 0
        case warn = 50   // 50%: warn + pattern detection -> biweekly
        case caution = 80 // 80%: disable on-demand patterns + downgrade Opus -> Sonnet
        case critical = 95 // 95%: disable all non-essential AI; keep recovery prescription only
        case exhausted = 100 // 100%: 503 everything
    }

    // ── State (cached for hot reads) ──────────────

    private var cachedYearMonth: String?
    private var cachedSpendCents: Int = 0
    private var cachedThreshold: ThrottleLevel = .none

    // ── Per-feature sub-budgets ───────────────────
    //
    // In-memory monthly spend per `caller` tag. Cheaper than per-feature DB
    // rows, accurate enough for a single-replica deployment. Resets when the
    // month rolls over (mirrors `cachedYearMonth`).
    //
    // Only callers with an entry in `subBudgetCapCents(for:)` are gated;
    // every other caller falls through to the global cap.
    private var subSpendCents: [String: Int] = [:]
    private var subBudgetYearMonth: String?

    /// Per-feature monthly caps in cents. Env-overridable so we can tighten
    /// or relax without a deploy. Coach defaults to $15/mo per the Coach
    /// Agent plan (`COACH_MONTHLY_BUDGET_CENTS`).
    nonisolated static func subBudgetCapCents(for caller: String) -> Int? {
        switch caller {
        case "coach":
            return Environment.get("COACH_MONTHLY_BUDGET_CENTS").flatMap(Int.init) ?? 1500
        default:
            return nil
        }
    }

    private func refreshSubBudgetIfNeeded() {
        let ym = Self.currentYearMonth()
        if subBudgetYearMonth != ym {
            subBudgetYearMonth = ym
            subSpendCents.removeAll(keepingCapacity: true)
        }
    }

    // MARK: - Public API

    /// Returns true if a call with the given worst-case cost can proceed.
    /// Callers pass the estimate BEFORE making the HTTP request.
    func canMakeCall(estimatedCostCents: Int, on req: Request) async -> Bool {
        await canMakeCall(estimatedCostCents: estimatedCostCents, caller: "_global", on: req)
    }

    /// Per-feature gate. If a sub-budget is registered for `caller` (see
    /// `subBudgetCapCents`), enforce both the global monthly cap AND the
    /// per-caller cap. Unknown callers only check the global cap.
    func canMakeCall(estimatedCostCents: Int, caller: String, on req: Request) async -> Bool {
        do {
            try await refreshIfNeeded(on: req)
            let projected = cachedSpendCents + max(0, estimatedCostCents)
            guard projected <= AIConfig.monthlyBudgetCents else { return false }

            if let cap = Self.subBudgetCapCents(for: caller) {
                refreshSubBudgetIfNeeded()
                let projectedSub = (subSpendCents[caller] ?? 0) + max(0, estimatedCostCents)
                if projectedSub > cap {
                    req.logger.warning(
                        "[ai_budget] sub-budget exhausted caller=\(caller) projected=\(projectedSub)c cap=\(cap)c"
                    )
                    return false
                }
            }
            return true
        } catch {
            // Fail open: if the DB is unreachable we don't want to bring down
            // every AI feature. The circuit breaker + post-call recordSpend
            // will catch true overruns shortly after.
            req.logger.error("AIBudgetTracker: refresh failed: \(error.localizedDescription)")
            return true
        }
    }

    /// Record actual usage after a successful Claude call. Upserts into
    /// ai_monthly_spend atomically. Returns the new ThrottleLevel so the
    /// caller can take action (log, downgrade, etc).
    @discardableResult
    func recordSpend(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        on req: Request
    ) async -> ThrottleLevel {
        await recordSpend(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            caller: "_global",
            on: req
        )
    }

    @discardableResult
    func recordSpend(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        caller: String,
        on req: Request
    ) async -> ThrottleLevel {
        let costMicrodollars = costInMicrodollars(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
        let costCents = max(1, costMicrodollars / 10_000)

        let ym = Self.currentYearMonth()

        do {
            try await upsert(yearMonth: ym, deltaCents: costCents, on: req)
            try await refreshIfNeeded(on: req, force: true)
        } catch {
            req.logger.error(
                "AIBudgetTracker: persist failed model=\(model) cost=\(costCents)c err=\(error.localizedDescription)"
            )
        }

        // Sub-budget bookkeeping (in-memory; resets monthly).
        if Self.subBudgetCapCents(for: caller) != nil {
            refreshSubBudgetIfNeeded()
            subSpendCents[caller, default: 0] += costCents
        }

        let level = thresholdLevel(for: cachedSpendCents)
        if level.rawValue > cachedThreshold.rawValue {
            await applyThresholdChange(from: cachedThreshold, to: level, on: req)
            cachedThreshold = level
            try? await persistThreshold(yearMonth: ym, level: level, on: req)
        }

        req.logger.info(
            "AI usage: model=\(model) caller=\(caller) in=\(inputTokens) out=\(outputTokens) cost=\(costCents)c spend=\(cachedSpendCents)/\(AIConfig.monthlyBudgetCents)c level=\(level.rawValue)%"
        )

        return level
    }

    /// Worst-case cost estimate for a planned call. Used by canMakeCall.
    /// Returns cents (rounded up, minimum 1 cent).
    nonisolated func estimateCostCents(
        model: String,
        estimatedInputTokens: Int,
        maxOutputTokens: Int
    ) -> Int {
        let micros = costInMicrodollars(
            model: model,
            inputTokens: estimatedInputTokens,
            outputTokens: maxOutputTokens
        )
        // Round UP so we don't undershoot the cap by fractions of a cent.
        return max(1, (micros + 9_999) / 10_000)
    }

    /// Current usage as a percentage of the monthly cap.
    func usagePercent(on req: Request) async -> Double {
        try? await refreshIfNeeded(on: req)
        guard AIConfig.monthlyBudgetCents > 0 else { return 0 }
        return Double(cachedSpendCents) / Double(AIConfig.monthlyBudgetCents) * 100
    }

    /// Current throttle level. Services check this to decide whether to
    /// downgrade models or skip non-essential features.
    func currentThrottleLevel(on req: Request) async -> ThrottleLevel {
        try? await refreshIfNeeded(on: req)
        return cachedThreshold
    }

    // MARK: - Cost computation (pure, nonisolated)

    nonisolated private func costInMicrodollars(
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) -> Int {
        switch model {
        case AIConfig.haikuModel:
            return inputTokens * 1 + outputTokens * 5
        case AIConfig.sonnetModel:
            return inputTokens * 3 + outputTokens * 15
        case AIConfig.opusModel:
            return inputTokens * 15 + outputTokens * 75
        default:
            return 0
        }
    }

    // MARK: - Threshold ladder

    nonisolated private func thresholdLevel(for spendCents: Int) -> ThrottleLevel {
        guard AIConfig.monthlyBudgetCents > 0 else { return .none }
        let pct = Double(spendCents) / Double(AIConfig.monthlyBudgetCents) * 100
        if pct >= 100 { return .exhausted }
        if pct >= 95 { return .critical }
        if pct >= 80 { return .caution }
        if pct >= 50 { return .warn }
        return .none
    }

    private func applyThresholdChange(
        from old: ThrottleLevel,
        to new: ThrottleLevel,
        on req: Request
    ) async {
        // Per AI_INTELLIGENCE_ENGINE.md §5.4 — log every transition so
        // operators can see the ladder firing in production.
        switch new {
        case .warn:
            req.logger.warning(
                "AI budget 50%: reducing pattern detection frequency to biweekly"
            )
        case .caution:
            req.logger.warning(
                "AI budget 80%: disabling on-demand pattern queries; downgrading Opus to Sonnet"
            )
        case .critical:
            req.logger.critical(
                "AI budget 95%: disabling all non-essential AI features; recovery prescription only"
            )
        case .exhausted:
            req.logger.critical(
                "AI budget 100%: AI features unavailable until next month; all requests will 503"
            )
        case .none:
            // Only reached on month rollover (handled via refreshIfNeeded).
            req.logger.info("AI budget reset for new month")
        }
    }

    // MARK: - Persistence

    private func refreshIfNeeded(on req: Request, force: Bool = false) async throws {
        let ym = Self.currentYearMonth()
        guard force || cachedYearMonth != ym else { return }

        if let row = try await AIMonthlySpend.find(ym, on: req.db) {
            cachedYearMonth = ym
            cachedSpendCents = row.spendCents
            cachedThreshold = ThrottleLevel(rawValue: row.thresholdApplied) ?? .none
        } else {
            // First call of the month — insert a zero row so the upsert path
            // is a simple UPDATE rather than handling INSERT-or-UPDATE.
            let fresh = AIMonthlySpend(yearMonth: ym)
            try? await fresh.create(on: req.db)
            cachedYearMonth = ym
            cachedSpendCents = 0
            cachedThreshold = .none
        }
    }

    private func upsert(yearMonth: String, deltaCents: Int, on req: Request) async throws {
        // Postgres-flavoured atomic increment via raw SQL — avoids the
        // read-modify-write race that a Fluent .save() would introduce when
        // multiple replicas record spend simultaneously.
        guard let sql = req.db as? any SQLDatabase else {
            // Fallback for non-SQL drivers (shouldn't happen with Fluent+Postgres).
            if let row = try await AIMonthlySpend.find(yearMonth, on: req.db) {
                row.spendCents += deltaCents
                try await row.save(on: req.db)
            } else {
                let row = AIMonthlySpend(yearMonth: yearMonth, spendCents: deltaCents)
                try await row.create(on: req.db)
            }
            return
        }

        // yearMonth is "YYYY-MM" (no SQL-special chars) and deltaCents is Int —
        // safe to inline. SQLKit's parameter-binding syntax isn't worth the
        // ceremony for two trusted values.
        try await sql.raw(
            SQLQueryString(stringLiteral: """
            INSERT INTO ai_monthly_spend (year_month, spend_cents, threshold_applied, created_at, updated_at)
            VALUES ('\(yearMonth)', \(deltaCents), 0, NOW(), NOW())
            ON CONFLICT (year_month) DO UPDATE
              SET spend_cents = ai_monthly_spend.spend_cents + EXCLUDED.spend_cents,
                  updated_at  = NOW()
            """)
        ).run()
    }

    private func persistThreshold(
        yearMonth: String,
        level: ThrottleLevel,
        on req: Request
    ) async throws {
        guard let row = try await AIMonthlySpend.find(yearMonth, on: req.db) else { return }
        row.thresholdApplied = level.rawValue
        try await row.save(on: req.db)
    }

    // MARK: - Helpers

    nonisolated static func currentYearMonth(date: Date = .init()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}

// MARK: - Convenience for typical estimates
//
// Services call these helpers so they don't have to remember per-feature
// input-token assumptions. Numbers come from AI_INTELLIGENCE_ENGINE.md §2.2.

enum AIBudgetEstimate {
    static func haiku(maxTokens: Int, estimatedInputTokens: Int = 1_500) -> Int {
        AIBudgetTracker.shared.estimateCostCents(
            model: AIConfig.haikuModel,
            estimatedInputTokens: estimatedInputTokens,
            maxOutputTokens: maxTokens
        )
    }

    static func sonnet(maxTokens: Int, estimatedInputTokens: Int = 3_000) -> Int {
        AIBudgetTracker.shared.estimateCostCents(
            model: AIConfig.sonnetModel,
            estimatedInputTokens: estimatedInputTokens,
            maxOutputTokens: maxTokens
        )
    }

    static func opus(maxTokens: Int, estimatedInputTokens: Int = 6_000) -> Int {
        AIBudgetTracker.shared.estimateCostCents(
            model: AIConfig.opusModel,
            estimatedInputTokens: estimatedInputTokens,
            maxOutputTokens: maxTokens
        )
    }
}
