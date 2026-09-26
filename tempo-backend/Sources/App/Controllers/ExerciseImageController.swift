import Fluent
import Vapor

// MARK: - ExerciseImageController

//
// Routes (wired manually in routes.swift, not via RouteCollection, because
// GET is public and POST is JWT-protected — two different route groups):
//   GET  /v1/exercise-images/:slug  — public, no auth. Serves the stored
//        bytes directly (not JSON) with a 1-year immutable Cache-Control so
//        AsyncImage/URLSession cache client-side. 404 if not generated yet.
//   POST /v1/exercise-images        — JWT auth. Idempotent: returns
//        {slug, url, status: "ready"} whether the image already existed or
//        was just generated (generation is synchronous, ~10-30s).

struct ExerciseImageController: Sendable {
    // MARK: - GET /v1/exercise-images/:slug

    @Sendable
    func show(req: Request) async throws -> Response {
        guard let slug = req.parameters.get("slug"), !slug.isEmpty else {
            throw Abort(.badRequest, reason: "Missing slug.")
        }

        guard let row = try await ExerciseImage.find(slug, on: req.db) else {
            throw Abort(.notFound)
        }

        let etag = "\"\(slug)\""
        if req.headers.first(name: "If-None-Match") == etag {
            return Response(status: .notModified)
        }

        let response = Response(status: .ok, body: .init(data: row.image))
        response.headers.replaceOrAdd(name: .contentType, value: row.contentType)
        response.headers.replaceOrAdd(name: "Cache-Control", value: "public, max-age=31536000, immutable")
        response.headers.replaceOrAdd(name: "ETag", value: etag)
        return response
    }

    // MARK: - POST /v1/exercise-images

    @Sendable
    func generate(req: Request) async throws -> Envelope<ExerciseImageResponseDTO> {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(ExerciseImageGenerateRequest.self)

        do {
            let result = try await ExerciseImageService.shared.getOrGenerate(
                name: body.name,
                equipment: body.equipment,
                muscleGroup: body.muscleGroup,
                movementPattern: body.movementPattern,
                instructions: body.instructions,
                userID: userID,
                on: req
            )
            return Envelope(data: result, requestID: req.requestID)
        } catch ExerciseImageService.ServiceError.notConfigured {
            throw Abort(.serviceUnavailable, reason: "Image generation isn't configured")
        } catch ExerciseImageService.ServiceError.dailyLimitReached {
            throw Abort(
                .tooManyRequests,
                reason: "Daily image generation limit reached (\(ExerciseImageService.dailyPerUserLimit)). Try again tomorrow."
            )
        } catch ExerciseImageService.ServiceError.budgetExhausted {
            throw Abort(.serviceUnavailable, reason: "Monthly image generation budget exhausted.")
        } catch ExerciseImageService.ServiceError.generationInProgress {
            throw Abort(.tooManyRequests, reason: "Image generation already in progress for this exercise. Try again shortly.")
        } catch let error as ExerciseImageGenerationError {
            req.logger.error("[exercise_image] generation failed: \(error)")
            throw Abort(.badGateway, reason: "Image generation failed. Try again later.")
        }
    }
}
