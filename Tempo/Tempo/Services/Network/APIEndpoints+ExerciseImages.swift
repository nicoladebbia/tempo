//
// APIEndpoints+ExerciseImages.swift
// Tempo
//

import Foundation

// MARK: - ExerciseImageGenerateRequestDTO

//
// POST /v1/exercise-images. GET /v1/exercise-images/:slug is intentionally
// NOT modeled here — it's public, unauthenticated and returns raw image
// bytes (not JSON), so ExerciseImageService fetches it with a plain
// URLSession call instead of routing it through APIClient's generic
// JSON-decoding `request<T>`.

struct ExerciseImageGenerateRequestDTO: Encodable, Sendable {
    let name: String
    let equipment: String
    let muscleGroup: String
    let movementPattern: String?
    let instructions: String?

    /// Backend serializes/expects snake_case; APIClient's encoder uses no
    /// global key strategy, so map explicitly — matching codebase convention
    /// (see AuthTokenResponse).
    enum CodingKeys: String, CodingKey {
        case name
        case equipment
        case muscleGroup = "muscle_group"
        case movementPattern = "movement_pattern"
        case instructions
    }
}

// MARK: - ExerciseImageGenerateResponseDTO

struct ExerciseImageGenerateResponseDTO: Decodable, Sendable {
    let slug: String
    let url: String
    let status: String
}

extension APIEndpoint where Response == ExerciseImageGenerateResponseDTO {
    static func generateExerciseImage() -> Self {
        APIEndpoint(path: "/v1/exercise-images", method: .post, requiresAuth: true, expectsEnvelope: true)
    }
}
