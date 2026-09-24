import Fluent
import Foundation
import Vapor

// MARK: - TrainerProgramImport

//
// One row per DISTINCT Trainer Program import session that has consumed a
// free-tier quota slot. See CreateTrainerProgramImports migration +
// TrainerProgramImportQuotaService for the gating logic that reads/writes
// this table.

final class TrainerProgramImport: Model, Content, @unchecked Sendable {
    static let schema = "trainer_program_imports"

    @ID(custom: "id")
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "session_id")
    var sessionID: String

    /// "YYYY-MM" in UTC — the calendar month this session's quota slot counts
    /// against. Matches AIMonthlySpend/AIBudgetTracker's yearMonth convention.
    @Field(key: "year_month")
    var yearMonth: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userID: String, sessionID: String, yearMonth: String) {
        self.id = id
        $user.id = userID
        self.sessionID = sessionID
        self.yearMonth = yearMonth
    }
}
