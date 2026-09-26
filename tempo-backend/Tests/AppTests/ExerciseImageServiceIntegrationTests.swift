@testable import App
import Fluent
import Foundation
import Testing
import Vapor

// MARK: - ExerciseImageService integration tests

//
// Against a REAL Postgres + Redis (same docker-compose services every other
// integration point in this suite uses — see TrainerProgramImportQuotaServiceTests
// for the pattern this mirrors). Every test injects FakeExerciseImageGenerator,
// never OpenAIImageGenerator — this suite must never spend real money.
//
// Each test uses a unique exercise name (UUID-suffixed) so slugs never
// collide with a previous run against the same persistent database.
//
// `.serialized`: shares the ExerciseImageBudgetTracker.shared/month-row
// singleton state across tests within this process.

@Suite("ExerciseImageService integration", .serialized)
struct ExerciseImageServiceIntegrationTests {
    private func withApp(_ body: (Application, Request) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            let req = Request(application: app, on: app.eventLoopGroup.next())
            try await body(app, req)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func uniqueExerciseName(_ label: String) -> String {
        "\(label) \(UUID().uuidString.prefix(8))"
    }

    // MARK: - Idempotent replay: existing row -> generator never called

    @Test func existingRowIsReturnedWithoutCallingGenerator() async throws {
        try await withApp { app, req in
            let name = uniqueExerciseName("Idempotent Replay Squat")
            let slug = ExerciseImageSlug.make(from: name)
            let row = ExerciseImage(slug: slug, contentType: "image/jpeg", image: Data([0x01]), prompt: "pre-existing")
            try await row.create(on: app.db)

            let generator = FakeExerciseImageGenerator(mode: .success)
            let service = ExerciseImageService(generator: generator)

            let response = try await service.getOrGenerate(
                name: name, equipment: "barbell", muscleGroup: "quads",
                movementPattern: nil, instructions: nil, userID: "user-\(UUID().uuidString)", on: req
            )

            #expect(response.slug == slug)
            #expect(response.status == "ready")
            #expect(generator.callCount == 0, "an already-generated slug must never call the generator")
        }
    }

    // MARK: - Not configured -> 503-mapped error, no row written, no spend

    @Test func notConfiguredThrowsAndWritesNothing() async throws {
        try await withApp { app, req in
            let name = uniqueExerciseName("Not Configured Deadlift")
            let slug = ExerciseImageSlug.make(from: name)
            let generator = FakeExerciseImageGenerator(mode: .notConfigured)
            let service = ExerciseImageService(generator: generator)

            await #expect(throws: ExerciseImageService.ServiceError.notConfigured) {
                try await service.getOrGenerate(
                    name: name, equipment: "barbell", muscleGroup: "back",
                    movementPattern: nil, instructions: nil, userID: "user-\(UUID().uuidString)", on: req
                )
            }

            let row = try await ExerciseImage.find(slug, on: app.db)
            #expect(row == nil, "a failed generation must not leave a row behind")
        }
    }

    // MARK: - Successful generation -> row persisted, second call is idempotent

    @Test func successfulGenerationPersistsRowAndIsIdempotentOnRetry() async throws {
        try await withApp { app, req in
            let name = uniqueExerciseName("Fresh Generation Row")
            let slug = ExerciseImageSlug.make(from: name)
            let generator = FakeExerciseImageGenerator(mode: .success)
            let service = ExerciseImageService(generator: generator)
            let userID = "user-\(UUID().uuidString)"

            let first = try await service.getOrGenerate(
                name: name, equipment: "dumbbell", muscleGroup: "shoulders",
                movementPattern: "vertical_push", instructions: "Press overhead.", userID: userID, on: req
            )
            #expect(first.status == "ready")
            #expect(generator.callCount == 1)

            let row = try await ExerciseImage.find(slug, on: app.db)
            #expect(row?.contentType == "image/jpeg")
            #expect(row?.image == FakeExerciseImageGenerator.onePixelJPEG)
            #expect(row?.prompt.contains(name) == true)

            // Second call for the same slug: row already exists, generator
            // must not be called again.
            let second = try await service.getOrGenerate(
                name: name, equipment: "dumbbell", muscleGroup: "shoulders",
                movementPattern: "vertical_push", instructions: "Press overhead.", userID: userID, on: req
            )
            #expect(second.status == "ready")
            #expect(generator.callCount == 1, "re-requesting an already-generated slug must not call the generator again")
        }
    }

    // MARK: - Per-user daily limit

    @Test func perUserDailyLimitBlocksTheFortyFirstDistinctExercise() async throws {
        try await withApp { _, req in
            let generator = FakeExerciseImageGenerator(mode: .success)
            let service = ExerciseImageService(generator: generator)
            let userID = "daily-limit-\(UUID().uuidString)"
            let label = UUID().uuidString.prefix(8)

            for i in 0 ..< ExerciseImageService.dailyPerUserLimit {
                let response = try await service.getOrGenerate(
                    name: "Daily Limit Exercise \(label) \(i)", equipment: "bodyweight", muscleGroup: "core",
                    movementPattern: nil, instructions: nil, userID: userID, on: req
                )
                #expect(response.status == "ready")
            }
            #expect(generator.callCount == ExerciseImageService.dailyPerUserLimit)

            await #expect(throws: ExerciseImageService.ServiceError.dailyLimitReached) {
                try await service.getOrGenerate(
                    name: "Daily Limit Exercise \(label) overflow", equipment: "bodyweight", muscleGroup: "core",
                    movementPattern: nil, instructions: nil, userID: userID, on: req
                )
            }
        }
    }
}
