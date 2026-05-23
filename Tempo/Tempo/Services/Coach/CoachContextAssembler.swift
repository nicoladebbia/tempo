//
// CoachContextAssembler.swift
// Tempo
//
// Builds the ~3K-token snapshot that the Coach agent reads at the top of
// every turn. Composed of six bands, each individually truncatable so the
// whole snapshot stays below the configured token ceiling even when the
// user has years of data on device.
//
// Bands (in render order, most → least important):
//
//   1. Identity                — name, age, weight, height, timezone, level
//   2. Relevant preferences    — top-N from PreferenceRetriever for this turn
//   3. Today live              — planned meals + actual logs + recovery
//   4. Last 7 days             — daily nutrition + training summary
//   5. Next 7 days             — upcoming planned meals + training + match days
//   6. Conversation summaries  — last 3 prior conversations' titles
//
// The assembler is pure-input-deterministic (given the same fixtures it
// emits the same string) so tests can pin exact output. Token estimation
// is character-count / 4 — coarse but standard for Anthropic models.
//

import Foundation
import SwiftData

@MainActor
final class CoachContextAssembler {

    /// Default token ceiling for the whole snapshot. The chat endpoint
    /// reserves the rest of the budget for tool schemas + user message +
    /// model output. 3000 leaves headroom for the agent loop.
    static let defaultTokenBudget = 3_000

    private let context: ModelContext
    private let now: Date

    init(context: ModelContext, now: Date = Date()) {
        self.context = context
        self.now = now
    }

    /// Build the snapshot. `userMessage` drives preference retrieval —
    /// pass the most recent user turn so relevant prefs bubble up.
    func snapshot(userMessage: String, tokenBudget: Int = defaultTokenBudget) -> Snapshot {
        let bands = [
            identityBand(),
            preferencesBand(userMessage: userMessage),
            todayBand(),
            lookBackBand(),
            lookForwardBand(),
            conversationSummariesBand(),
        ]

        // Render bands greedily until we hit the budget; truncate the last
        // partial band rather than splitting mid-band.
        var rendered: [String] = []
        var usedTokens = 0
        for band in bands {
            let bandTokens = estimateTokens(band)
            if usedTokens + bandTokens > tokenBudget {
                let remaining = max(0, tokenBudget - usedTokens)
                let truncated = truncate(band, toTokens: remaining)
                if !truncated.isEmpty { rendered.append(truncated) }
                break
            }
            rendered.append(band)
            usedTokens += bandTokens
        }

        let text = rendered.joined(separator: "\n\n")
        return Snapshot(
            text: text,
            estimatedTokens: estimateTokens(text),
            bandCount: rendered.count
        )
    }

    // MARK: - Bands

    func identityBand() -> String {
        let profileDesc = FetchDescriptor<UserProfile>()
        guard let profile = try? context.fetch(profileDesc).first else {
            return "## Identity\n(no profile on device)"
        }
        var lines: [String] = ["## Identity"]
        if !profile.displayName.isEmpty { lines.append("Name: \(profile.displayName)") }
        if !profile.identityLabel.isEmpty { lines.append("Identity: \(profile.identityLabel)") }
        if let age = profile.age { lines.append("Age: \(age)") }
        if let kg = profile.weightKg { lines.append("Weight: \(Int(kg))kg") }
        if let cm = profile.heightCm { lines.append("Height: \(Int(cm))cm") }
        lines.append("Timezone: \(profile.timezone)")
        lines.append("Level: \(profile.currentLevel) (XP \(profile.totalXP))")
        return lines.joined(separator: "\n")
    }

    func preferencesBand(userMessage: String) -> String {
        let activeDesc = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { $0.isActive }
        )
        let active = (try? context.fetch(activeDesc)) ?? []
        let ranked = PreferenceRetriever.retrieve(for: userMessage, from: active)
        guard !ranked.isEmpty else {
            return "## Preferences\n(none learned yet)"
        }
        var lines: [String] = ["## Preferences"]
        for pref in ranked {
            let short = pref.id.uuidString.prefix(8)
            let verified = pref.userVerified ? " ✓" : ""
            let conf = String(format: "%.2f", pref.confidence)
            lines.append("- [\(short)] (\(pref.subject), conf=\(conf)\(verified)) \(pref.text)")
        }
        return lines.joined(separator: "\n")
    }

    func todayBand() -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let plannedDesc = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { $0.dayDate >= today && $0.dayDate < tomorrow }
        )
        let planned = ((try? context.fetch(plannedDesc)) ?? [])
            .sorted { $0.scheduledTime < $1.scheduledTime }

        let logDesc = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { $0.dayDate >= today && $0.dayDate < tomorrow }
        )
        let logs = ((try? context.fetch(logDesc)) ?? []).sorted { $0.loggedAt < $1.loggedAt }

        var lines: [String] = ["## Today (\(formatDate(today)))"]
        if planned.isEmpty && logs.isEmpty {
            lines.append("(no plan or logs)")
            return lines.joined(separator: "\n")
        }
        if !planned.isEmpty {
            lines.append("Planned:")
            for meal in planned {
                let cals = Int(meal.totalCalories)
                let p = Int(meal.totalProtein)
                lines.append(
                    "  • \(meal.scheduledTime) \(meal.mealName) — \(cals)kcal / \(p)gP [\(meal.status.rawValue)]"
                )
            }
        }
        if !logs.isEmpty {
            lines.append("Logged:")
            for log in logs {
                let time = formatTime(log.loggedAt)
                let cals = Int(log.totalCalories)
                lines.append("  • \(time) \(log.mealType.displayName) — \(cals)kcal")
            }
        }
        return lines.joined(separator: "\n")
    }

    func lookBackBand() -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today)!
        let logDesc = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { $0.dayDate >= weekAgo && $0.dayDate < today }
        )
        let logs = (try? context.fetch(logDesc)) ?? []
        guard !logs.isEmpty else {
            return "## Last 7 days\n(no meal logs)"
        }
        let byDay = Dictionary(grouping: logs) { cal.startOfDay(for: $0.dayDate) }
        var lines: [String] = ["## Last 7 days"]
        for day in byDay.keys.sorted(by: >) {
            let cals = Int(byDay[day]?.reduce(0) { $0 + $1.totalCalories } ?? 0)
            let n = byDay[day]?.count ?? 0
            lines.append("- \(formatDate(day)): \(n) meals, \(cals)kcal")
        }
        return lines.joined(separator: "\n")
    }

    func lookForwardBand() -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekOut = cal.date(byAdding: .day, value: 7, to: today)!
        let plannedDesc = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { $0.dayDate > today && $0.dayDate < weekOut }
        )
        let planned = ((try? context.fetch(plannedDesc)) ?? [])
            .sorted { $0.dayDate < $1.dayDate }
        guard !planned.isEmpty else {
            return "## Next 7 days\n(no planned meals)"
        }
        let byDay = Dictionary(grouping: planned) { cal.startOfDay(for: $0.dayDate) }
        var lines: [String] = ["## Next 7 days"]
        for day in byDay.keys.sorted() {
            let n = byDay[day]?.count ?? 0
            let cals = Int(byDay[day]?.reduce(0) { $0 + $1.totalCalories } ?? 0)
            lines.append("- \(formatDate(day)): \(n) planned meals, \(cals)kcal")
        }
        return lines.joined(separator: "\n")
    }

    /// Conversation summaries — populated by P6 once `CoachConversation`
    /// exists in the schema. Until then this is a no-op band so the
    /// assembler can ship before P6 wires it.
    func conversationSummariesBand() -> String {
        // P6 hook: query CoachConversation, take the 3 most recent
        // titleSummary fields, render. For now, contribute nothing so
        // the budget isn't spent on placeholder text.
        ""
    }

    // MARK: - Tokenization + truncation

    /// Coarse character-count / 4 estimator. Matches what other Tempo
    /// services use for budget gating (see AIBudgetTracker.execute).
    static func estimateTokens(_ s: String) -> Int {
        max(1, s.count / 4)
    }

    func estimateTokens(_ s: String) -> Int { Self.estimateTokens(s) }

    /// Trim `s` to roughly `toTokens` tokens. Lines are preserved; we
    /// truncate by dropping trailing lines until the estimate fits.
    func truncate(_ s: String, toTokens: Int) -> String {
        guard toTokens > 0 else { return "" }
        var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while estimateTokens(lines.joined(separator: "\n")) > toTokens, lines.count > 1 {
            lines.removeLast()
        }
        if lines.count < s.split(separator: "\n").count {
            lines.append("(…truncated to fit context)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Format helpers

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: d)
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - Snapshot

    struct Snapshot: Equatable {
        let text: String
        let estimatedTokens: Int
        let bandCount: Int
    }
}
