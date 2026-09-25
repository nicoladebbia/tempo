import Fluent
import Foundation

// MARK: - ExerciseImage

//
// One AI-generated HD picture per exercise, keyed by ExerciseImageSlug.make(name:).
// Generated once (via OpenAIImageGenerator, gated by ExerciseImageBudgetTracker +
// a per-user daily limit) and served to every user by
// GET /v1/exercise-images/:slug — this row IS the cache, there is no separate
// CDN/blob store yet.
//
// Deliberately NOT `Content` — the image bytes must never be serialized into a
// JSON envelope (huge base64 blob); ExerciseImageController streams `image` as
// a raw `Response` body instead. See ExerciseImageResponseDTO for the JSON
// shape actually returned by the endpoints.

final class ExerciseImage: Model, @unchecked Sendable {
    static let schema = "exercise_images"

    @ID(custom: "slug", generatedBy: .user)
    var id: String?

    @Field(key: "content_type")
    var contentType: String

    @Field(key: "image")
    var image: Data

    @Field(key: "prompt")
    var prompt: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(slug: String, contentType: String, image: Data, prompt: String) {
        id = slug
        self.contentType = contentType
        self.image = image
        self.prompt = prompt
    }
}
