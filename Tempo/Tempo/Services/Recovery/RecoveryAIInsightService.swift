//
// RecoveryAIInsightService.swift
// Tempo
//
// Generates a single personalised daily recovery paragraph via Claude Haiku,
// reusing the server-side nutrition Claude proxy (the Anthropic key never
// ships in the app — ADR-018 / INTELLIGENCE_REMEDIATION_PLAN.md §3).
//
// The result is cached one row per calendar day in RecoveryInsight
// (type .aiDailyParagraph) so repeated view appearances do not re-call the
// proxy.
//

import Foundation
import os
import SwiftData

// MARK: - Errors

enum RecoveryAIInsightError: LocalizedError {
    case noRecoveryData
    case apiFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noRecoveryData:
            "No recovery data available yet."
        case let .apiFailed(error):
            "Couldn't generate today's insight: \(error.localizedDescription)"
        }
    }
}

// MARK: - RecoveryAIInsightService

@Observable
final class RecoveryAIInsightService: @unchecked Sendable {
    private let apiClient: APIClient
    private let logger = Logger.recovery

    private let maxRetries = 2
    private let baseRetryDelay: Double = 1.0

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public

    /// Returns today's cached AI paragraph if one exists, otherwise calls
    /// Haiku, caches the result for the current calendar day, and returns it.
    @MainActor
    func paragraph(
        for recovery: DailyRecovery,
        modelContext: ModelContext
    ) async throws -> String {
        if let cached = cachedParagraph(modelContext: modelContext) {
            logger.info("[recovery_insight] cache hit for today — no proxy call")
            return cached
        }

        let prompt = Self.buildPrompt(from: recovery)
        let text = try await sendWithRetry(prompt: prompt)

        let insight = RecoveryInsight(
            date: Calendar.current.startOfDay(for: Date()),
            type: .aiDailyParagraph,
            title: "Today's Read",
            body: text,
            confidence: 1.0
        )
        modelContext.insert(insight)
        try? modelContext.save()

        return text
    }

    // MARK: - Cache

    /// Looks up a cached `.aiDailyParagraph` insight whose `date` falls within
    /// today's calendar day. `RecoveryInsight.date` is a raw timestamp, so we
    /// match against a startOfDay..<startOfNextDay range.
    @MainActor
    func cachedParagraph(modelContext: ModelContext) -> String? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return nil
        }
        let typeRaw = RecoveryInsightType.aiDailyParagraph.rawValue
        var descriptor = FetchDescriptor<RecoveryInsight>(
            predicate: #Predicate { insight in
                insight.typeRaw == typeRaw &&
                    insight.date >= dayStart &&
                    insight.date < dayEnd
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.body
    }

    // MARK: - Prompt

    /// Builds a structured prompt containing every available WHOOP field for
    /// today. Missing optionals are omitted rather than sent as "nil" so the
    /// model only reasons over real measurements.
    static func buildPrompt(from r: DailyRecovery) -> String {
        var lines: [String] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { lines.append("- \(label): \(value)") }
        }

        add("Recovery score", "\(Int(r.recoveryScore))%")
        add("Recovery zone", r.recoveryZoneRaw)
        add("HRV (RMSSD)", r.hrvRmssd.map { String(format: "%.0f ms", $0) })
        add("Resting heart rate", r.restingHR.map { String(format: "%.0f bpm", $0) })
        add("Blood oxygen (SpO2)", r.spo2.map { String(format: "%.1f%%", $0) })
        add("Skin temperature deviation", r.skinTemp.map { String(format: "%.1f°C", $0) })
        add("Sleep duration", r.sleepHours.map { String(format: "%.1f h", $0) })
        add("Sleep performance", r.sleepScore.map { String(format: "%.0f%%", $0) })
        add("Sleep efficiency", r.sleepEfficiency.map { String(format: "%.0f%%", $0) })
        add("Sleep consistency", r.sleepConsistency.map { String(format: "%.0f%%", $0) })
        add("Deep sleep", r.deepSleepMin.map { "\($0) min" })
        add("REM sleep", r.remSleepMin.map { "\($0) min" })
        add("Light sleep", r.lightSleepMin.map { "\($0) min" })
        add("Awake time", r.awakeMin.map { "\($0) min" })
        add("Sleep debt", r.sleepDebt.map { String(format: "%.1f h", $0) })
        add("Respiratory rate", r.respiratoryRate.map { String(format: "%.1f br/min", $0) })
        add("Day strain", r.strain.map { String(format: "%.1f", $0) })
        add("Average heart rate", r.avgHR.map { String(format: "%.0f bpm", $0) })
        add("Max heart rate", r.maxHR.map { String(format: "%.0f bpm", $0) })
        add("Calories burned", r.caloriesBurned.map { String(format: "%.0f kcal", $0) })

        return """
        Today's WHOOP data for this user:
        \(lines.joined(separator: "\n"))

        Write the daily read described in the system instructions using ONLY \
        the values above.
        """
    }

    static let systemPrompt = """
    You are Tempo's recovery coach. You get one user's WHOOP biometrics \
    for today. Write a SHORT read: 2-3 sentences, 55 words MAX. Lead with \
    the single most important takeaway for today (e.g. "Push hard" or \
    "Hold back"). Cite at most TWO numbers — only the ones that drive that \
    takeaway — and ignore every other metric; do not list or recite them. \
    End with ONE concrete action. Be direct and punchy, not exhaustive. \
    Plain text only: no markdown, no asterisks, no dashes as bullets, no \
    headings, no greeting. Output only the read, nothing else.
    """

    // MARK: - Proxy call (mirrors NutritionCoachService.sendWithRetry)

    private func sendWithRetry(prompt: String) async throws -> String {
        var lastError: Error?

        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: "haiku",
                    system: Self.systemPrompt,
                    userMessage: prompt,
                    maxTokens: 400,
                    temperature: 0.4,
                    caller: "recovery_insight"
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                    body: body
                )
                logger.info("[recovery_insight] Haiku response received (attempt \(attempt))")
                return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as APIError {
                lastError = error
                logger.warning("[recovery_insight] proxy error (attempt \(attempt)): \(String(describing: error))")
                guard error.isRetryable, attempt < maxRetries else { break }
                let delay = baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))
            } catch {
                lastError = error
                logger.error("[recovery_insight] unexpected error: \(error.localizedDescription)")
                break
            }
        }

        throw RecoveryAIInsightError.apiFailed(lastError ?? APIError.unknown(statusCode: -1))
    }
}
