import Fluent
import Vapor

// MARK: - AIMonthlySpend Model
//
// Per AI_INTELLIGENCE_ENGINE.md §5.4 + INTELLIGENCE_REMEDIATION_PLAN.md §5.
// One row per calendar month, identified by "YYYY-MM". Updated atomically
// by AIBudgetTracker on every Claude call. Threshold ladder action level
// (50/80/95/100%) is persisted so process restarts don't re-fire warnings.

final class AIMonthlySpend: Model, Content, @unchecked Sendable {
    static let schema = "ai_monthly_spend"

    @ID(custom: "year_month", generatedBy: .user)
    var id: String?

    @Field(key: "spend_cents")
    var spendCents: Int

    /// Per-feature spend for caller="coach". Subset of `spendCents`.
    /// Enforced alongside the global cap via AIConfig.coachMonthlyBudgetCents.
    /// Per Coach v2.1 plan.
    @Field(key: "coach_spend_cents")
    var coachSpendCents: Int

    /// Highest threshold rung already applied this month.
    /// 0 = none, 50/80/95/100 = §5.4 ladder levels.
    @Field(key: "threshold_applied")
    var thresholdApplied: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        yearMonth: String,
        spendCents: Int = 0,
        coachSpendCents: Int = 0,
        thresholdApplied: Int = 0
    ) {
        self.id = yearMonth
        self.spendCents = spendCents
        self.coachSpendCents = coachSpendCents
        self.thresholdApplied = thresholdApplied
    }
}
