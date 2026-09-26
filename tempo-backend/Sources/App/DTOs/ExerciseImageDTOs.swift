import Vapor

// MARK: - ExerciseImageGenerateRequest

//
// POST /v1/exercise-images body. Wire is snake_case (global decoder uses
// .convertFromSnakeCase). None of these fields hit the "ID/URL acronym"
// decoding pitfall (session_id -> sessionId, never sessionID) — no field
// here is spelled with a trailing ID/URL, so plain camelCase properties
// decode correctly with no explicit CodingKeys. Verified by
// ExerciseImageRequestDecodingTests.

struct ExerciseImageGenerateRequest: Content {
    let name: String
    let equipment: String
    let muscleGroup: String
    let movementPattern: String?
    let instructions: String?
}

// MARK: - ExerciseImageResponseDTO

//
// Response for both GET-status-free idempotent replay and POST /v1/exercise-images.
// `url` is deliberately lowercase (not `imageURL`) so `.convertToSnakeCase`
// emits plain "url" — the acronym pitfall only bites on decode of an
// uppercase-acronym Swift property, and this project's convention (see
// CoachClaudeProxyService / TrainingProgramImportController fixes) is to
// dodge it entirely by not spelling the property with a trailing acronym.

struct ExerciseImageResponseDTO: Content {
    let slug: String
    let url: String
    let status: String

    static func ready(slug: String, baseURL: String) -> ExerciseImageResponseDTO {
        ExerciseImageResponseDTO(slug: slug, url: "\(baseURL)/v1/exercise-images/\(slug)", status: "ready")
    }
}
