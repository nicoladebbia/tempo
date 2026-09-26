import Fluent
import Foundation

// MARK: - ExerciseImageMonthlySpend

//
// One row per calendar month ("YYYY-MM"), tracked by ExerciseImageBudgetTracker.

final class ExerciseImageMonthlySpend: Model, @unchecked Sendable {
    static let schema = "exercise_image_monthly_spend"

    @ID(custom: "year_month", generatedBy: .user)
    var id: String?

    @Field(key: "spend_cents")
    var spendCents: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(yearMonth: String, spendCents: Int = 0) {
        id = yearMonth
        self.spendCents = spendCents
    }
}
