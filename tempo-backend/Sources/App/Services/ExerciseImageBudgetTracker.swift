import Fluent
import SQLKit
import Vapor

// MARK: - ExerciseImageBudgetTracker

//
// Hard ceiling on OpenAI image-generation spend per calendar month. Mirrors
// AIBudgetTracker's pre-flight-gate + atomic-upsert shape, against its own
// `exercise_image_monthly_spend` table (flat 4c/image cost, not token-metered,
// so it doesn't fit AIBudgetTracker's Claude-specific cost model).
//
// Global cap: IMAGE_MONTHLY_BUDGET_CENTS env var, default 2000 (= $20 at
// OpenAIImageGenerator.costCents (4c) each -> ~500 images/month).

actor ExerciseImageBudgetTracker {
    static let shared = ExerciseImageBudgetTracker()

    /// Monthly image-generation spend cap in cents. Default $20 (2000c).
    static var monthlyBudgetCents: Int {
        Environment.get("IMAGE_MONTHLY_BUDGET_CENTS").flatMap(Int.init) ?? 2000
    }

    private var cachedYearMonth: String?
    private var cachedSpendCents: Int = 0

    /// True if one more generation (at the given cost) would stay within cap.
    func canGenerate(estimatedCostCents: Int = OpenAIImageGenerator.costCents, on req: Request) async -> Bool {
        do {
            try await refreshIfNeeded(on: req)
            return cachedSpendCents + estimatedCostCents <= Self.monthlyBudgetCents
        } catch {
            // Fail open — same rationale as AIBudgetTracker: a DB hiccup
            // shouldn't take down image generation. recordSpend's own
            // failure log plus the CLI/route logs catch true overruns.
            req.logger.error("ExerciseImageBudgetTracker: refresh failed: \(error.localizedDescription)")
            return true
        }
    }

    @discardableResult
    func recordSpend(costCents: Int = OpenAIImageGenerator.costCents, on req: Request) async -> Int {
        let ym = Self.currentYearMonth()
        do {
            try await upsert(yearMonth: ym, deltaCents: costCents, on: req)
            try await refreshIfNeeded(on: req, force: true)
        } catch {
            req.logger.error("ExerciseImageBudgetTracker: persist failed cost=\(costCents)c err=\(error.localizedDescription)")
        }
        req.logger.info("Exercise image spend: +\(costCents)c, month total \(cachedSpendCents)/\(Self.monthlyBudgetCents)c")
        return cachedSpendCents
    }

    // MARK: - Persistence

    private func refreshIfNeeded(on req: Request, force: Bool = false) async throws {
        let ym = Self.currentYearMonth()
        guard force || cachedYearMonth != ym else { return }

        if let row = try await ExerciseImageMonthlySpend.find(ym, on: req.db) {
            cachedYearMonth = ym
            cachedSpendCents = row.spendCents
        } else {
            let fresh = ExerciseImageMonthlySpend(yearMonth: ym)
            try? await fresh.create(on: req.db)
            cachedYearMonth = ym
            cachedSpendCents = 0
        }
    }

    private func upsert(yearMonth: String, deltaCents: Int, on req: Request) async throws {
        guard let sql = req.db as? any SQLDatabase else {
            if let row = try await ExerciseImageMonthlySpend.find(yearMonth, on: req.db) {
                row.spendCents += deltaCents
                try await row.save(on: req.db)
            } else {
                try await ExerciseImageMonthlySpend(yearMonth: yearMonth, spendCents: deltaCents).create(on: req.db)
            }
            return
        }

        // yearMonth is "YYYY-MM" (no SQL-special chars) and deltaCents is Int —
        // safe to inline, matching AIBudgetTracker.upsert.
        try await sql.raw(
            SQLQueryString(stringLiteral: """
            INSERT INTO exercise_image_monthly_spend (year_month, spend_cents, created_at, updated_at)
            VALUES ('\(yearMonth)', \(deltaCents), NOW(), NOW())
            ON CONFLICT (year_month) DO UPDATE
              SET spend_cents = exercise_image_monthly_spend.spend_cents + EXCLUDED.spend_cents,
                  updated_at  = NOW()
            """)
        ).run()
    }

    nonisolated static func currentYearMonth(date: Date = .init()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
