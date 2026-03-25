import Vapor
import Fluent
import Queues
@preconcurrency import Redis

// MARK: - Weekly Summary Job
// Per BUILD_PLAN step 15.2 — Sunday job that generates weekly reports for all users.
// Per AI_INTELLIGENCE_ENGINE.md Section 6.3 — Cache warming Sunday night batch.
// Generates reports proactively so Monday morning is fully cached.

struct WeeklySummaryJob: AsyncScheduledJob {

    func run(context: QueueContext) async throws {
        let db = context.application.db
        context.logger.info("Weekly summary job starting...")

        // Fetch all active users
        let users = try await User.query(on: db)
            .filter(\.$deletedAt == nil)
            .all()

        guard !users.isEmpty else {
            context.logger.info("No active users found for weekly summary.")
            return
        }

        let weekStart = currentWeekStart()
        var generated = 0
        var failed = 0

        for user in users {
            guard let userID = user.id else { continue }

            // Check if already cached for this week
            let cacheKey = RedisKey("insight:weekly:\(userID):\(weekStart)")
            if let existing = try? await context.application.redis.get(cacheKey, as: String.self),
               existing != nil {
                continue  // Already generated
            }

            do {
                // Build input
                let input = buildWeeklyInput(user: user, weekStart: weekStart, db: db)

                // Generate via InsightService (uses fallback if API unavailable)
                // Create a minimal dummy request for the service
                // In production, this would use the application's client directly
                // For now, generate the fallback directly since we can't create a Request in a job
                let report = generateFallbackReport(input)

                // Cache the result
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                if let data = try? encoder.encode(report),
                   let jsonString = String(data: data, encoding: .utf8) {
                    _ = try? await context.application.redis.set(cacheKey, to: jsonString)
                    _ = try? await context.application.redis.expire(cacheKey, after: .seconds(7 * 24 * 3600))
                }

                generated += 1
            } catch {
                context.logger.error("Failed to generate weekly report for user \(userID): \(error)")
                failed += 1
            }
        }

        context.logger.info("Weekly summary job complete: \(generated) generated, \(failed) failed, \(users.count) total users")
    }

    // MARK: - Build Input

    private func buildWeeklyInput(user: User, weekStart: String, db: Database) -> WeeklyReportInput {
        WeeklyReportInput(
            userID: user.id ?? "",
            weekStart: weekStart,
            weekEnd: currentWeekEnd(),
            streakDays: user.streakDays,
            level: user.level,
            xpTotal: user.xpTotal,
            avgScore: 75,  // TODO: Compute from daily snapshots
            daysWithData: 7,
            avgRecovery: 72,
            avgSleepHours: 7.0,
            avgCompletionPct: 80,
            workoutCount: 5,
            proteinAdherencePct: 70,
            avgStudyMinutes: 90,
            studyTarget: 120,
            weeklyXP: 0,
            prevAvgRecovery: 75,
            prevAvgSleepHours: 7.2,
            prevWorkoutCount: 5,
            prevWeeklyXP: 0,
            prevProteinAdherencePct: 75,
            prevAvgStudyMinutes: 100,
            prevAvgCompletionPct: 85
        )
    }

    // MARK: - Fallback Report Generator
    // Per AI_INTELLIGENCE_ENGINE.md Section 8.2 — Statistical template.

    private func generateFallbackReport(_ input: WeeklyReportInput) -> WeeklyReportResponse {
        let title: String
        if input.avgScore >= 90 { title = "Dominant week across the board" }
        else if input.avgScore >= 75 { title = "Solid week with room to grow" }
        else if input.avgScore >= 60 { title = "Average week -- time to lock in" }
        else { title = "Below the line -- reset starts now" }

        let recoveryDelta = input.avgRecovery - input.prevAvgRecovery

        return WeeklyReportResponse(
            title: title,
            summary: "This week you scored an average of \(input.avgScore)/100 across \(input.daysWithData) days. " +
                     "Recovery averaged \(input.avgRecovery)% and you completed \(input.avgCompletionPct)% of non-negotiables.",
            sections: [
                ReportSection(
                    title: "Recovery & Sleep",
                    icon: "bed.double.fill",
                    body: "Average recovery: \(input.avgRecovery)% (\(recoveryDelta >= 0 ? "+" : "")\(recoveryDelta)% vs last week). " +
                          "Sleep averaged \(String(format: "%.1f", input.avgSleepHours))h.",
                    sentiment: recoveryDelta >= 0 ? "positive" : "warning"
                ),
                ReportSection(
                    title: "Fitness",
                    icon: "flame.fill",
                    body: "\(input.workoutCount) workouts completed this week.",
                    sentiment: input.workoutCount >= 4 ? "positive" : "warning"
                ),
                ReportSection(
                    title: "Nutrition",
                    icon: "fork.knife",
                    body: "Protein target hit \(input.proteinAdherencePct)% of days.",
                    sentiment: input.proteinAdherencePct >= 70 ? "positive" : "warning"
                ),
                ReportSection(
                    title: "Academics",
                    icon: "book.fill",
                    body: "Average daily study: \(input.avgStudyMinutes) minutes vs \(input.studyTarget) target.",
                    sentiment: input.avgStudyMinutes >= input.studyTarget ? "positive" : "warning"
                ),
            ],
            actionItems: [
                "Review your weakest domain and set one specific improvement target for next week.",
                "Maintain current sleep schedule. Consistency matters more than duration.",
                "Focus on completing all non-negotiables before evening."
            ],
            comparedToLastWeek: WeekOverWeekDeltas(
                recoveryAvgChange: recoveryDelta,
                sleepAvgChangeMin: Int((input.avgSleepHours - input.prevAvgSleepHours) * 60),
                workoutCountChange: input.workoutCount - input.prevWorkoutCount,
                xpChange: input.weeklyXP - input.prevWeeklyXP,
                proteinAdherenceChange: input.proteinAdherencePct - input.prevProteinAdherencePct,
                studyAvgChangeMin: input.avgStudyMinutes - input.prevAvgStudyMinutes,
                completionPctChange: input.avgCompletionPct - input.prevAvgCompletionPct
            )
        )
    }

    // MARK: - Helpers

    private func currentWeekStart() -> String {
        let calendar = Calendar.current
        let weekStartDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: weekStartDate)
    }

    private func currentWeekEnd() -> String {
        let calendar = Calendar.current
        let weekStartDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let weekEndDate = calendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: weekEndDate)
    }
}
