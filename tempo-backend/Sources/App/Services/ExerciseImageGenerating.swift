import Foundation
import Vapor

// MARK: - ExerciseImageGenerating

//
// Injectable image-generation boundary. There is NO image API key configured
// yet and this service must NEVER be called against the real OpenAI API in
// tests — every test that exercises ExerciseImageService's actual
// get-or-generate flow (Tests/AppTests/ExerciseImageServiceIntegrationTests.swift,
// DB+Redis backed) constructs its own `ExerciseImageService(generator:)`
// with FakeExerciseImageGenerator (Tests/AppTests/Stubs), never the
// `.shared` singleton (which defaults to real OpenAIImageGenerator() and is
// only what the controller/CLI use in production). Real generation only
// activates once OPENAI_API_KEY is set (see OpenAIImageGenerator.isConfigured).

protocol ExerciseImageGenerating: Sendable {
    /// Generates one image for `prompt`. Throws `.notConfigured` when no API
    /// key is set (the caller maps that to HTTP 503), or `.apiError`/
    /// `.decodingFailed` on an unexpected upstream response.
    func generateImage(prompt: String, on req: Request) async throws -> GeneratedExerciseImage
}

struct GeneratedExerciseImage: Sendable {
    let data: Data
    let contentType: String
}

enum ExerciseImageGenerationError: Error, Equatable {
    /// No OPENAI_API_KEY configured. Controller maps this to 503.
    case notConfigured
    case apiError(Int)
    case decodingFailed
}
