import Fluent

// MARK: - CreateTrainerProgramImports

//
// Per docs/BACKEND_API.md-adjacent Trainer Program import quota (fix #1/#2):
// one row per DISTINCT import "session" (a client-generated UUID sent on
// every network call of a single import — transcribe batches + the
// structure call all share it). The first call of a new session consumes
// one month's quota slot; every later call with the same session_id is a
// free retry/continuation, detected via the (user_id, session_id) unique
// index. Free tier: 2 sessions per calendar month (UTC); Pro/allowlisted
// users are unlimited and never consume this table's quota gate (see
// ProEntitlement + TrainerProgramImportQuotaService).

struct CreateTrainerProgramImports: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("trainer_program_imports")
            .id()
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("session_id", .string, .required)
            .field("year_month", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "user_id", "session_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("trainer_program_imports").delete()
    }
}
