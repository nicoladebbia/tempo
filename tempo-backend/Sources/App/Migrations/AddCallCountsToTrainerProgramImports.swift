import Fluent

// MARK: - AddCallCountsToTrainerProgramImports

//
// Additive: per-session counters so one free quota slot cannot buy unlimited
// Claude calls by re-sending the same session_id. Existing rows default to 0.

struct AddCallCountsToTrainerProgramImports: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("trainer_program_imports")
            .field("transcribe_calls", .int, .required, .sql(.default(0)))
            .field("structure_calls", .int, .required, .sql(.default(0)))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("trainer_program_imports")
            .deleteField("transcribe_calls")
            .deleteField("structure_calls")
            .update()
    }
}
