//
// TrainerProgramImportService.swift
// Tempo
//
// Structures extracted program text via the shared nutrition Claude proxy
// (server-side key — ADR-018 / INTELLIGENCE_REMEDIATION_PLAN.md §3), mirroring
// MonthlyReviewCoach's retry/backoff shape. The prompt + JSON parsing
// themselves live in TrainerProgramParser (pure, unit-tested); this type is
// the thin network wrapper around it.
//

import Foundation
import os

// MARK: - TrainerProgramImportService

@Observable
final class TrainerProgramImportService: @unchecked Sendable {
    private let apiClient: APIClient
    private let logger = Logger.training
    private let maxRetries = 2
    private let baseRetryDelay: Double = 1.0

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    enum ImportError: Error, LocalizedError {
        case signedOut
        case api(APIError)
        case parse(TrainerProgramParser.ParseError)

        var errorDescription: String? {
            switch self {
            case .signedOut:
                "AI import needs you signed in. Sign in and try again."
            case let .api(error):
                error.userMessage
            case let .parse(error):
                error.errorDescription
            }
        }
    }

    /// Structures `sourceText` (already OCR'd/extracted, or pasted) into a
    /// program via the Sonnet proxy. A signed-out user gets `.signedOut`
    /// immediately (the proxy answers 401) — there's no local fallback, this
    /// genuinely needs the model.
    func structureProgram(from sourceText: String) async throws -> TrainerProgramParser.ParsedProgram {
        var lastError: APIError?
        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: "sonnet",
                    system: TrainerProgramParser.systemPrompt,
                    userMessage: TrainerProgramParser.userMessage(sourceText: sourceText),
                    // A multi-source import's combined transcript (several
                    // lift + conditioning sessions across files) structures
                    // into a bigger JSON payload than a single-page program.
                    maxTokens: 4096,
                    temperature: 0,
                    caller: "trainer_program_import"
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                    body: body
                )
                return try TrainerProgramParser.parse(response.text)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as TrainerProgramParser.ParseError {
                throw ImportError.parse(error)
            } catch let error as APIError {
                if case .unauthorized = error {
                    logger.info("\(DebugTrace.prefix)[trainer_program_import] 401 — signed out")
                    throw ImportError.signedOut
                }
                lastError = error
                guard error.isRetryable, attempt < maxRetries else {
                    throw ImportError.api(error)
                }
                logger
                    .warning(
                        "\(DebugTrace.prefix)[trainer_program_import] retryable error attempt=\(attempt): \(String(describing: error))"
                    )
                try await Task.sleep(for: .seconds(baseRetryDelay * pow(2.0, Double(attempt))))
            } catch {
                logger.error("\(DebugTrace.prefix)[trainer_program_import] unexpected: \(error.localizedDescription)")
                throw ImportError.api(.unknown(statusCode: -1))
            }
        }
        throw ImportError.api(lastError ?? .unknown(statusCode: -1))
    }
}
