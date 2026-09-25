import Fluent

// MARK: - CreateExerciseImages

//
// Per feat/exercise-images — one AI-generated HD picture per exercise,
// generated once on the backend and reused by every user (no per-user
// storage, no CDN yet: the row itself IS the cache; GET /v1/exercise-images/:slug
// serves the bytes directly with long-lived Cache-Control so AsyncImage /
// URLSession do the client-side caching for us).
//
// `slug` is the primary key (deterministic from the exercise name — see
// ExerciseImageSlug — so generation is naturally idempotent: a second
// request for the same exercise either reads the existing row or races on
// this same key, backstopped by the unique/primary-key constraint).

struct CreateExerciseImages: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("exercise_images")
            .field("slug", .string, .identifier(auto: false))
            .field("content_type", .string, .required)
            .field("image", .data, .required)
            .field("prompt", .string, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("exercise_images").delete()
    }
}
