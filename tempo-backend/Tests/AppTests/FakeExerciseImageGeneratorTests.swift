@testable import App
import Testing
import Vapor

// MARK: - FakeExerciseImageGenerator

//
// Exercises the ExerciseImageGenerating protocol boundary directly (no DB,
// no Postgres needed — just an Application + a bare Request) to prove the
// injectable-generator pattern actually swaps in for tests, per the "do NOT
// spend money" constraint: ExerciseImageService/ExerciseImageController are
// never tested against OpenAIImageGenerator.

@Suite("FakeExerciseImageGenerator")
struct FakeExerciseImageGeneratorTests {
    private func withRequest(_ body: (Request) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            let req = Request(application: app, on: app.eventLoopGroup.next())
            try await body(req)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test func successModeReturnsJPEGBytes() async throws {
        try await withRequest { req in
            let generator = FakeExerciseImageGenerator(mode: .success)
            let result = try await generator.generateImage(prompt: "a squat", on: req)
            #expect(result.contentType == "image/jpeg")
            #expect(!result.data.isEmpty)
            #expect(generator.callCount == 1)
        }
    }

    @Test func notConfiguredModeThrows() async throws {
        try await withRequest { req in
            let generator = FakeExerciseImageGenerator(mode: .notConfigured)
            await #expect(throws: ExerciseImageGenerationError.notConfigured) {
                try await generator.generateImage(prompt: "a squat", on: req)
            }
        }
    }

    @Test func apiErrorModeThrowsWithStatusCode() async throws {
        try await withRequest { req in
            let generator = FakeExerciseImageGenerator(mode: .apiError(500))
            await #expect(throws: ExerciseImageGenerationError.apiError(500)) {
                try await generator.generateImage(prompt: "a squat", on: req)
            }
        }
    }
}
