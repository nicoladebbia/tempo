//
// MonthlyReviewCoach.swift
// Tempo
//
// D4 §17.2 — the once-a-month Sonnet call that turns the aggregated month +
// interview into the report. Mirrors DailyReadinessCoach's proxy/retry shape
// (server-side key, 402 → silent nil) with the cost controls the AI guardrail
// requires:
//   • ≤1 call/month — enforced by the CALLER via MonthlyReview.summaryText
//     (non-nil = spent; generateMonthlySummary guards before calling here).
//   • maxTokens 800, model "sonnet" via the generic text proxy — richer
//     reasoning is warranted once a month, never on the daily path.
//
// Returns plain text (it's a report, not a schedule) — no parse step, so the
// only failure modes are transport-level: nil on 402 / offline / empty.
//

import Foundation
import OSLog

final class MonthlyReviewCoach: Sendable {
    private let apiClient: APIClient
    private let logger = Logger.training
    private let maxRetries = 2
    private let baseRetryDelay: Double = 1.0

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// The Sonnet report, or nil (offline / 402 / empty). The caller decides
    /// what nil means — it does NOT mark the month spent, so a failed attempt
    /// retries on the next app-open inside the review window.
    func summary(data: MonthlyReviewData, interview: MonthInterviewSnapshot) async -> String? {
        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: "sonnet",
                    system: MonthlyReviewPrompt.system,
                    userMessage: MonthlyReviewPrompt.userMessage(data: data, interview: interview),
                    maxTokens: 800,
                    temperature: 0.5,
                    caller: "monthly_review"
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                    body: body
                )
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch is CancellationError {
                return nil
            } catch let error as APIError {
                // 402 = not Pro / no consent → silently no report this month.
                if case .subscriptionRequired = error {
                    logger.info("\(DebugTrace.prefix)[monthly_review] 402 gate — no summary")
                    return nil
                }
                guard error.isRetryable, attempt < maxRetries else {
                    logger.warning("\(DebugTrace.prefix)[monthly_review] failed attempt=\(attempt): \(String(describing: error))")
                    return nil
                }
                try? await Task.sleep(for: .seconds(baseRetryDelay * pow(2.0, Double(attempt))))
            } catch {
                logger.error("\(DebugTrace.prefix)[monthly_review] unexpected: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }
}
