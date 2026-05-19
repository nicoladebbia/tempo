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

        // Longitudinal read when yesterday's context exists; otherwise the
        // today-only read (cold-start / reinstall / missed day).
        let prompt: String
        let system: String
        if let yctx = yesterdayContext(modelContext: modelContext) {
            prompt = Self.buildLongitudinalPrompt(today: recovery, yesterday: yctx)
            system = Self.longitudinalSystemPrompt
        } else {
            prompt = Self.buildPrompt(from: recovery)
            system = Self.systemPrompt
        }
        let text = try await sendWithRetry(system: system, prompt: prompt)

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

    // MARK: - Yesterday context (longitudinal)

    /// Everything we know about yesterday: the read we gave, the WHOOP
    /// numbers, what was eaten/trained, and which non-negotiables were hit.
    /// All fields optional — a sparse day still produces useful context.
    struct YesterdayContext {
        var tipGiven: String?
        var recovery: DailyRecovery
        var mealCalories: Double?
        var mealProtein: Double?
        var mealCount: Int
        var trainedExercises: Int
        var trainingVolume: Double
        var ranKm: Double?
        var nonNegotiablesDone: Int?
        var nonNegotiablesTotal: Int?
    }

    /// Assembles yesterday's context, or nil when there's no yesterday
    /// recovery row (cold-start / reinstall / missed day) — caller then
    /// falls back to the today-only prompt.
    @MainActor
    func yesterdayContext(modelContext: ModelContext) -> YesterdayContext? {
        let cal = Calendar.current
        let yStart = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()
        guard let yEnd = cal.date(byAdding: .day, value: 1, to: yStart) else { return nil }

        // Yesterday's recovery is the anchor — no row → no longitudinal read.
        var recDesc = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date == yStart }
        )
        recDesc.fetchLimit = 1
        guard let rec = try? modelContext.fetch(recDesc).first else { return nil }

        var ctx = YesterdayContext(
            recovery: rec, mealCount: 0, trainedExercises: 0, trainingVolume: 0
        )

        // The tip we gave yesterday (the .aiDailyParagraph for that day).
        let typeRaw = RecoveryInsightType.aiDailyParagraph.rawValue
        var tipDesc = FetchDescriptor<RecoveryInsight>(
            predicate: #Predicate { i in
                i.typeRaw == typeRaw && i.date >= yStart && i.date < yEnd
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        tipDesc.fetchLimit = 1
        ctx.tipGiven = (try? modelContext.fetch(tipDesc).first)?.body

        // Nutrition — MealLog.dayDate is day-normalized (== match).
        let mealDesc = FetchDescriptor<MealLog>(
            predicate: #Predicate { $0.dayDate == yStart }
        )
        if let meals = try? modelContext.fetch(mealDesc), !meals.isEmpty {
            ctx.mealCount = meals.count
            ctx.mealCalories = meals.reduce(0) { $0 + $1.totalCalories }
            ctx.mealProtein = meals.reduce(0) { $0 + $1.totalProtein }
        }

        // Training — ExerciseHistory.date is day-normalized; RunSession.date
        // is NOT, so it needs a range.
        let exDesc = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.date == yStart }
        )
        if let ex = try? modelContext.fetch(exDesc), !ex.isEmpty {
            ctx.trainedExercises = ex.count
            ctx.trainingVolume = ex.reduce(0) { $0 + $1.totalVolume }
        }
        let runDesc = FetchDescriptor<RunSession>(
            predicate: #Predicate { $0.date >= yStart && $0.date < yEnd }
        )
        if let runs = try? modelContext.fetch(runDesc), !runs.isEmpty {
            ctx.ranKm = runs.reduce(0) { $0 + $1.distanceMeters } / 1000.0
        }

        // Adherence — DailyAccountability.date is day-normalized.
        var accDesc = FetchDescriptor<DailyAccountability>(
            predicate: #Predicate { $0.date == yStart }
        )
        accDesc.fetchLimit = 1
        if let acc = try? modelContext.fetch(accDesc).first {
            ctx.nonNegotiablesDone = acc.completedCount
            ctx.nonNegotiablesTotal = acc.totalCount
        }

        return ctx
    }

    // MARK: - Weekly recap (Mondays)

    /// The Monday (start-of-day) that begins the week containing `date`.
    /// Foundation weekday: Sunday=1 ... Saturday=7, so Monday=2.
    private static func weekStartMonday(for date: Date) -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: todayStart) // 1...7
        // Days since Monday: Mon→0, Tue→1, ... Sun→6.
        let daysSinceMonday = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -daysSinceMonday, to: todayStart) ?? todayStart
    }

    /// Returns the cached or freshly-generated weekly recap, or nil when:
    /// it isn't Monday, there are <3 days of recovery data in the trailing
    /// 7 days, or the proxy call fails. Cached one row per week keyed by
    /// that week's Monday `date` (so it's a hit all day Monday).
    @MainActor
    func weeklyRecap(modelContext: ModelContext) async throws -> String? {
        let cal = Calendar.current
        let now = Date()
        // Foundation: Sunday=1, Monday=2.
        guard cal.component(.weekday, from: now) == 2 else { return nil }

        let monday = Self.weekStartMonday(for: now)
        let typeRaw = RecoveryInsightType.aiWeeklyRecap.rawValue

        // Cache hit: a recap row for this week's Monday already exists.
        var cacheDesc = FetchDescriptor<RecoveryInsight>(
            predicate: #Predicate { $0.typeRaw == typeRaw && $0.date == monday }
        )
        cacheDesc.fetchLimit = 1
        if let cached = try? modelContext.fetch(cacheDesc).first {
            logger.info("[weekly_recap] cache hit for week of \(monday) — no proxy call")
            return cached.body
        }

        // Trailing 7 days: the week that just ended (the 7 days before today).
        guard let windowStart = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) else {
            return nil
        }
        let windowEnd = cal.startOfDay(for: now)

        let recDesc = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < windowEnd },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let recoveries = (try? modelContext.fetch(recDesc)) ?? []
        guard recoveries.count >= 3 else {
            logger.info("[weekly_recap] only \(recoveries.count) days of data — skipping")
            return nil
        }

        let mealDesc = FetchDescriptor<MealLog>(
            predicate: #Predicate { $0.dayDate >= windowStart && $0.dayDate < windowEnd }
        )
        let meals = (try? modelContext.fetch(mealDesc)) ?? []

        let exDesc = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < windowEnd }
        )
        let exercises = (try? modelContext.fetch(exDesc)) ?? []

        let runDesc = FetchDescriptor<RunSession>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < windowEnd }
        )
        let runs = (try? modelContext.fetch(runDesc)) ?? []

        let accDesc = FetchDescriptor<DailyAccountability>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < windowEnd }
        )
        let accountability = (try? modelContext.fetch(accDesc)) ?? []

        let prompt = Self.buildWeeklyPrompt(
            recoveries: recoveries,
            meals: meals,
            exercises: exercises,
            runs: runs,
            accountability: accountability
        )
        let text = try await sendWithRetry(system: Self.weeklySystemPrompt, prompt: prompt)

        let insight = RecoveryInsight(
            date: monday,
            type: .aiWeeklyRecap,
            title: "Last Week",
            body: text,
            confidence: 1.0
        )
        modelContext.insert(insight)
        try? modelContext.save()
        return text
    }

    static let weeklySystemPrompt = """
    You are Tempo's recovery coach writing a WEEKLY review on Monday \
    morning. You get aggregate stats for the 7 days that just ended: \
    recovery trend, sleep, training, nutrition, and how many \
    non-negotiables the user hit. Write a reflective recap: 4-6 \
    sentences, 100 words MAX. Call out the single clearest pattern of \
    the week (good or bad), cite 2-3 concrete numbers, and name one \
    thing that improved and one thing to fix this coming week. State \
    adherence and trends as FACTS — never claim outcomes happened \
    BECAUSE the user followed your advice; weekly noise is real. End \
    with one specific focus for the week ahead. Plain text only: no \
    markdown, asterisks, dashes-as-bullets, headings, or greeting. \
    Output only the recap.
    """

    /// Aggregates the trailing-7-day window into a compact fact sheet.
    static func buildWeeklyPrompt(
        recoveries: [DailyRecovery],
        meals: [MealLog],
        exercises: [ExerciseHistory],
        runs: [RunSession],
        accountability: [DailyAccountability]
    ) -> String {
        var lines: [String] = []

        let scores = recoveries.map(\.recoveryScore)
        if let first = scores.first, let last = scores.last, !scores.isEmpty {
            let avg = scores.reduce(0, +) / Double(scores.count)
            lines.append(String(format: "- Recovery: %d days logged, avg %.0f%%, started %.0f%% ended %.0f%%",
                                 scores.count, avg, first, last))
        }
        let sleeps = recoveries.compactMap(\.sleepHours)
        if !sleeps.isEmpty {
            lines.append(String(format: "- Sleep: avg %.1f h/night over %d nights",
                                 sleeps.reduce(0, +) / Double(sleeps.count), sleeps.count))
        }
        let strains = recoveries.compactMap(\.strain)
        if !strains.isEmpty {
            lines.append(String(format: "- Avg day strain: %.1f", strains.reduce(0, +) / Double(strains.count)))
        }
        if !meals.isEmpty {
            let kcal = meals.reduce(0) { $0 + $1.totalCalories }
            let protein = meals.reduce(0) { $0 + $1.totalProtein }
            let loggedDays = Set(meals.map(\.dayDate)).count
            lines.append(String(format: "- Nutrition: logged on %d days, total %.0f kcal, %.0fg protein",
                                 loggedDays, kcal, protein))
        }
        if !exercises.isEmpty {
            let volume = exercises.reduce(0) { $0 + $1.totalVolume }
            let trainDays = Set(exercises.map(\.date)).count
            lines.append("- Training: \(trainDays) days, \(exercises.count) exercises, \(Int(volume)) total volume")
        }
        if !runs.isEmpty {
            let km = runs.reduce(0) { $0 + $1.distanceMeters } / 1000.0
            lines.append(String(format: "- Running: %d runs, %.1f km total", runs.count, km))
        }
        if !accountability.isEmpty {
            let done = accountability.reduce(0) { $0 + $1.completedCount }
            let total = accountability.reduce(0) { $0 + $1.totalCount }
            if total > 0 {
                lines.append("- Non-negotiables: \(done)/\(total) hit across \(accountability.count) days")
            }
        }

        return """
        Aggregate stats for the 7 days that just ended:
        \(lines.joined(separator: "\n"))

        Write the weekly recap described in the system instructions using \
        ONLY the values above.
        """
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

    // MARK: - Longitudinal prompt (yesterday → today)

    static let longitudinalSystemPrompt = """
    You are Tempo's recovery coach. You get yesterday's read you gave the \
    user, what they actually did yesterday (sleep, food, training, which \
    daily non-negotiables they hit), and today's WHOOP numbers. Write a \
    SHORT read: 3-4 sentences, 70 words MAX. First, connect yesterday to \
    today: note what they did yesterday and how today's recovery looks \
    relative to it, referencing 1-2 concrete facts (e.g. "you hit your \
    bedtime and protein; recovery climbed to 78"). You MAY note if they \
    followed or skipped yesterday's advice, but state it as fact — NEVER \
    claim their day is good or bad BECAUSE they listened to you; recovery \
    is noisy and causation is often false. Then give ONE concrete action \
    for today. Direct and specific, not exhaustive. Plain text only: no \
    markdown, asterisks, dashes-as-bullets, headings, or greeting. Output \
    only the read.
    """

    /// Builds the longitudinal user message: yesterday's tip + what the
    /// user actually did + today's WHOOP. Sparse yesterday fields are
    /// omitted so the model only reasons over real data.
    static func buildLongitudinalPrompt(
        today: DailyRecovery,
        yesterday y: YesterdayContext
    ) -> String {
        var yLines: [String] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { yLines.append("- \(label): \(value)") }
        }

        add("Recovery score", "\(Int(y.recovery.recoveryScore))%")
        add("Sleep duration", y.recovery.sleepHours.map { String(format: "%.1f h", $0) })
        add("Sleep consistency", y.recovery.sleepConsistency.map { String(format: "%.0f%%", $0) })
        add("Day strain", y.recovery.strain.map { String(format: "%.1f", $0) })
        if let kcal = y.mealCalories, y.mealCount > 0 {
            add("Food logged", String(format: "%.0f kcal, %.0fg protein across %d meals",
                                      kcal, y.mealProtein ?? 0, y.mealCount))
        }
        if y.trainedExercises > 0 {
            add("Training", "\(y.trainedExercises) exercises, \(Int(y.trainingVolume)) total volume")
        }
        if let km = y.ranKm, km > 0 {
            add("Run", String(format: "%.1f km", km))
        }
        if let done = y.nonNegotiablesDone, let total = y.nonNegotiablesTotal, total > 0 {
            add("Non-negotiables hit", "\(done)/\(total)")
        }

        var tLines: [String] = []
        func addT(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { tLines.append("- \(label): \(value)") }
        }
        addT("Recovery score", "\(Int(today.recoveryScore))%")
        addT("HRV (RMSSD)", today.hrvRmssd.map { String(format: "%.0f ms", $0) })
        addT("Resting heart rate", today.restingHR.map { String(format: "%.0f bpm", $0) })
        addT("Sleep duration", today.sleepHours.map { String(format: "%.1f h", $0) })
        addT("Sleep consistency", today.sleepConsistency.map { String(format: "%.0f%%", $0) })
        addT("Sleep debt", today.sleepDebt.map { String(format: "%.1f h", $0) })
        addT("Day strain", today.strain.map { String(format: "%.1f", $0) })

        let tip = (y.tipGiven?.isEmpty == false)
            ? y.tipGiven!
            : "(no read was given yesterday)"

        return """
        The read you gave the user YESTERDAY:
        "\(tip)"

        What the user actually did YESTERDAY:
        \(yLines.joined(separator: "\n"))

        The user's WHOOP data TODAY:
        \(tLines.joined(separator: "\n"))

        Write the longitudinal read described in the system instructions \
        using ONLY the values above.
        """
    }

    // MARK: - Proxy call (mirrors NutritionCoachService.sendWithRetry)

    private func sendWithRetry(system: String, prompt: String) async throws -> String {
        var lastError: Error?

        for attempt in 0 ... maxRetries {
            do {
                let body = NutritionProxyTextRequest(
                    model: "haiku",
                    system: system,
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
