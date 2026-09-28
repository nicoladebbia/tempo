//
// TrainerFeedbackService.swift
// Tempo
//
// trainer-feedback-tests — network wrapper for "Trainer sent changes",
// mirroring `TrainerProgramImportService`'s retry/backoff shape exactly. The
// prompt + JSON parsing live in `TrainerFeedbackParser` (pure, unit-tested);
// this is the thin network call around it, hitting the dedicated
// POST /v1/training/program-import/feedback route — NOT the quota-gated
// transcribe/structure routes, so this never spends one of the athlete's
// free monthly imports.
//

import Foundation
import os

// MARK: - TrainerFeedbackService

@Observable
final class TrainerFeedbackService: @unchecked Sendable {
    private let apiClient: APIClient
    private let logger = Logger.training
    private let maxRetries = 2
    private let baseRetryDelay: Double = 1.0

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    enum FeedbackError: Error, LocalizedError {
        case signedOut
        case api(APIError)
        case parse(TrainerFeedbackParser.ParseError)

        var errorDescription: String? {
            switch self {
            case .signedOut:
                "Sign in to read trainer changes with AI."
            case let .api(error):
                error.userMessage
            case let .parse(error):
                error.errorDescription
            }
        }
    }

    /// Structures `feedbackText` (pasted, or OCR'd from a screenshot) into
    /// raw edits via the Sonnet proxy. A signed-out user gets `.signedOut`
    /// immediately (the route answers 401) — there's no local fallback.
    func structureFeedback(from feedbackText: String) async throws -> [RawTrainerFeedbackEdit] {
        var lastError: APIError?
        for attempt in 0 ... maxRetries {
            do {
                let body = ProgramFeedbackRequestDTO(
                    model: "sonnet",
                    system: TrainerFeedbackParser.systemPrompt,
                    userMessage: TrainerFeedbackParser.userMessage(feedbackText: feedbackText),
                    maxTokens: 1500,
                    temperature: 0,
                    caller: "trainer_feedback_edit"
                )
                let response: ProgramFeedbackResponseDTO = try await apiClient.request(
                    APIEndpoint<ProgramFeedbackResponseDTO>.trainerProgramFeedback(),
                    body: body
                )
                return try TrainerFeedbackParser.parse(response.text)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as TrainerFeedbackParser.ParseError {
                throw FeedbackError.parse(error)
            } catch let error as APIError {
                if case .unauthorized = error {
                    logger.info("\(DebugTrace.prefix)[trainer_feedback_edit] 401 — signed out")
                    throw FeedbackError.signedOut
                }
                lastError = error
                guard error.isRetryable, attempt < maxRetries else {
                    throw FeedbackError.api(error)
                }
                logger
                    .warning(
                        "\(DebugTrace.prefix)[trainer_feedback_edit] retryable error attempt=\(attempt): \(String(describing: error))"
                    )
                try await Task.sleep(for: .seconds(baseRetryDelay * pow(2.0, Double(attempt))))
            } catch {
                logger.error("\(DebugTrace.prefix)[trainer_feedback_edit] unexpected: \(error.localizedDescription)")
                throw FeedbackError.api(.unknown(statusCode: -1))
            }
        }
        throw FeedbackError.api(lastError ?? .unknown(statusCode: -1))
    }
}
