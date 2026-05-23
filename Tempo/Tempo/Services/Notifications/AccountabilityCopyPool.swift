//
// AccountabilityCopyPool.swift
// Tempo
//
// Created by Tempo on 09/05/2026.
//
//

import Foundation
import os

// MARK: - CopyTier

// Reads weighted, intensity-aware drill-sergeant copy from
// Resources/AccountabilityCopy.json and applies recency suppression so the
// user doesn't see the same line twice in a week.
//
// Per MODULE_ACCOUNTABILITY.md §6.1 (D7) — last-7-day exclude, last-14-day
// weight halving. Per §7.4 (D45-49) — intensity tiers map 1:1 to four copy
// pools: Gentle Coach (1) → gentle, Firm Coach (2) → firm,
// Drill Sergeant (3) → drillSergeant, Savage Mode (4) → savage.

enum CopyTier: String {
    case gentle
    case firm
    case urgent
    case critical
    case allClear
    // Arena (event-driven): leaderboard change, challenge event, XP milestone.
    case arena
    // Social: Focus Timer fired while inside the social-hours window.
    case social
}

// MARK: - CopyIntensity

enum CopyIntensity: String, CaseIterable {
    case gentle
    case firm
    case drillSergeant
    case savage

    /// Maps the persisted `UserSettings.notificationIntensity` (1–4, validated)
    /// to a copy pool. Each setting level now has a distinct pool — Drill
    /// Sergeant (3) no longer collapses into Firm.
    init(notificationIntensity: Int) {
        switch notificationIntensity {
        case 1: self = .gentle
        case 2: self = .firm
        case 3: self = .drillSergeant
        case 4: self = .savage
        default: self = .firm
        }
    }

    /// Graceful degrade order if a tier is missing this intensity's array in
    /// the JSON (e.g. a partially-authored channel). Never silently drops to
    /// the terse code fallback while a less-intense pool still exists.
    var degradeChain: [CopyIntensity] {
        switch self {
        case .gentle: [.gentle, .firm]
        case .firm: [.firm, .gentle]
        case .drillSergeant: [.drillSergeant, .firm, .savage]
        case .savage: [.savage, .drillSergeant, .firm]
        }
    }
}

// MARK: - CopyContext

struct CopyContext {
    var remaining: Int = 0
    var done: Int = 0
    var total: Int = 0
    var studyDone: String = "0"
    var studyTarget: String = "0"
    var timeRemaining: String = ""
    var streakDays: Int = 0
    // Arena
    var rank: Int = 0
    var previousRank: Int = 0
    var challengeName: String = ""
    var xpMilestone: Int = 0
    var opponentName: String = ""
    // Social
    var minutesIntoSocial: Int = 0
}

// MARK: - AccountabilityCopyPool

final class AccountabilityCopyPool: @unchecked Sendable {
    static let shared = AccountabilityCopyPool()

    private let logger = Logger(subsystem: "app.tempo", category: "CopyPool")
    private let pools: [String: [String: [String]]]

    /// UserDefaults key prefix for tracking message-last-shown dates.
    private let recencyKeyPrefix = "tempo.copyPool.lastSeen."

    private struct PoolFile: Decodable {
        let version: Int
        let tiers: [String: [String: [String]]]
    }

    private init() {
        guard let url = Bundle.main.url(forResource: "AccountabilityCopy", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PoolFile.self, from: data)
        else {
            Logger(subsystem: "app.tempo", category: "CopyPool")
                .error("Failed to load AccountabilityCopy.json — copy will fall back to inline strings")
            pools = [:]
            return
        }
        pools = decoded.tiers
    }

    /// Pick a copy variant for the given tier + intensity, applying recency
    /// suppression and template variable substitution. Falls back to a short
    /// fixed string if the pool is empty (resource load failure).
    func pick(tier: CopyTier, intensity: CopyIntensity, context: CopyContext) -> String {
        let tierPools = pools[tier.rawValue]
        // Try the requested intensity, then degrade (drillSergeant → firm, etc.)
        // before falling back to the terse code string.
        let pool = intensity.degradeChain
            .lazy
            .compactMap { tierPools?[$0.rawValue] }
            .first(where: { !$0.isEmpty }) ?? []
        guard !pool.isEmpty else {
            return fallback(for: tier, context: context)
        }
        let chosen = selectWithRecency(pool: pool)
        markUsed(chosen)
        return interpolate(chosen, with: context)
    }

    // MARK: - Selection

    /// Pick a message preferring those not seen in the last 7 days, with
    /// halved weight for those seen in 8-14 days. If every message has been
    /// seen recently, fall back to uniform random.
    private func selectWithRecency(pool: [String]) -> String {
        let now = Date()
        let weights: [(String, Double)] = pool.map { msg in
            let weight = recencyWeight(for: msg, now: now)
            return (msg, weight)
        }
        let totalWeight = weights.reduce(0.0) { $0 + $1.1 }
        if totalWeight <= 0 {
            return pool.randomElement() ?? pool[0]
        }
        var roll = Double.random(in: 0 ..< totalWeight)
        for (msg, weight) in weights {
            roll -= weight
            if roll <= 0 {
                return msg
            }
        }
        return weights.last?.0 ?? pool[0]
    }

    /// Return the selection weight for `message`: 0.0 if shown in last 7 days,
    /// 0.5 in 8-14 days, 1.0 otherwise (including never-shown).
    private func recencyWeight(for message: String, now: Date) -> Double {
        guard let last = lastSeenDate(for: message) else {
            return 1.0
        }
        let days = now.timeIntervalSince(last) / 86400
        if days < 7 {
            return 0.0
        }
        if days < 14 {
            return 0.5
        }
        return 1.0
    }

    private func lastSeenDate(for message: String) -> Date? {
        let key = recencyKey(for: message)
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    private func markUsed(_ message: String) {
        UserDefaults.standard.set(Date(), forKey: recencyKey(for: message))
    }

    private func recencyKey(for message: String) -> String {
        // Hash the message so we don't store full sentences as defaults keys.
        recencyKeyPrefix + String(message.hashValue)
    }

    // MARK: - Template substitution

    private func interpolate(_ template: String, with context: CopyContext) -> String {
        var result = template
        let pairs: [(String, String)] = [
            ("{remaining}", String(context.remaining)),
            ("{done}", String(context.done)),
            ("{total}", String(context.total)),
            ("{studyDone}", context.studyDone),
            ("{studyTarget}", context.studyTarget),
            ("{timeRemaining}", context.timeRemaining),
            ("{streakDays}", String(context.streakDays)),
            ("{rank}", String(context.rank)),
            ("{previousRank}", String(context.previousRank)),
            ("{challengeName}", context.challengeName),
            ("{xpMilestone}", String(context.xpMilestone)),
            ("{opponentName}", context.opponentName),
            ("{minutesIntoSocial}", String(context.minutesIntoSocial)),
        ]
        for (placeholder, value) in pairs {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    private func fallback(for tier: CopyTier, context: CopyContext) -> String {
        switch tier {
        case .gentle:
            "\(context.remaining) tasks left. \(context.done)/\(context.total) done."
        case .firm:
            "\(context.remaining) tasks incomplete. \(context.timeRemaining) remaining."
        case .urgent:
            "\(context.timeRemaining) before evening. \(context.remaining) tasks."
        case .critical:
            "Final warning. \(context.remaining) tasks undone."
        case .allClear:
            "ALL CLEAR. \(context.total)/\(context.total) complete."
        case .arena:
            "Arena update. You're #\(context.rank)."
        case .social:
            "Social hours. Focus session running — stay on it."
        }
    }
}
