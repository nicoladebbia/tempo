//
// BehaviorObserver.swift
// Tempo
//
// Nightly job that compares the last 7 days of `PlannedMeal` against
// `MealLog` and mints `LearnedPreference` entries from behavioral patterns
// the user never explicitly stated. Also reinforces existing observed
// preferences when behavior continues to confirm them, and applies the
// daily decay to every active preference.
//
// Design notes:
//
// • Runs from `DailyResetCoordinator.runIfNeeded` so it piggy-backs on the
//   coordinator's once-per-day gate — no separate scheduler.
//
// • Pure read-then-write against `ModelContext` on the main actor. No
//   network calls, no Claude. Behavior signals are deterministic patterns
//   we can detect without a model.
//
// • Generated preferences carry `source = .observed` and start at a low
//   confidence (0.5) so the assembler weights them less than user-stated
//   ones. They climb only with continued evidence (`markReinforced`).
//
// • Idempotent — a duplicate run on the same day either no-ops (decay
//   guards on `lastSeenAt`) or re-asserts the same finding by reinforcing
//   instead of inserting (dedup by `subject` + similar `text`).
//
// Detected patterns (v1):
//
//   1. Meal skipped ≥3 of last 7 days for a specific meal type
//      → `meal_timing.<type>` observed-pref: "Often skips <meal>"
//   2. Meal time consistently shifted ≥30min from scheduled (≥4 of 7 days,
//      same direction) → `meal_timing.<type>` observed-pref:
//      "Eats <meal> ~<delta>min <earlier|later> than planned"
//   3. Reinforcement: if a meal's actual time falls within ±15min of the
//      planned time for ≥5 of 7 days AND a matching pref exists, call
//      `markReinforced()` on it.
//

import Foundation
import OSLog
import SwiftData

@MainActor
enum BehaviorObserver {

    private static let logger = Logger(subsystem: "com.tempo.app", category: "BehaviorObserver")

    /// Run the full observer pass: pattern detection, reinforcement, decay.
    /// Safe to call multiple times per day — `applyDailyDecay` short-circuits
    /// on `lastSeenAt`, and the inserter dedupes by subject + text.
    static func run(context: ModelContext, now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -7, to: today) else {
            logger.error("BehaviorObserver: failed to compute 7-day window")
            return
        }

        let plannedDesc = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= windowStart && meal.dayDate < today
            }
        )
        let logDesc = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { meal in
                meal.dayDate >= windowStart && meal.dayDate < today
            }
        )

        let planned = (try? context.fetch(plannedDesc)) ?? []
        let logs = (try? context.fetch(logDesc)) ?? []
        let activePrefs = fetchActivePreferences(in: context)

        let proposals = detectPatterns(
            planned: planned,
            logs: logs,
            calendar: calendar
        )

        for proposal in proposals {
            apply(proposal: proposal, existing: activePrefs, in: context, now: now)
        }

        // Daily decay on every active preference. `applyDailyDecay` is a
        // no-op for prefs already touched today (reinforcement above), so
        // freshly-confirmed prefs don't get penalized.
        for pref in activePrefs {
            pref.applyDailyDecay(at: now)
        }

        try? context.save()
        logger.info(
            "BehaviorObserver: window=\(windowStart)..\(today) planned=\(planned.count) logs=\(logs.count) proposals=\(proposals.count)"
        )
    }

    // MARK: - Pattern detection (pure)

    /// Pure function — exposed for unit tests. Returns proposals without
    /// touching the context; `apply` is responsible for inserting/reinforcing.
    static func detectPatterns(
        planned: [PlannedMeal],
        logs: [MealLog],
        calendar: Calendar = .current
    ) -> [BehaviorProposal] {
        var out: [BehaviorProposal] = []

        // Group planned + logged by (day, meal type). PlannedMeal uses
        // `mealName` ("Breakfast"/"Lunch"/...); MealLog uses `mealType`
        // (enum displayName). We normalize on lowercased name.
        let plannedByDayType = Dictionary(grouping: planned) {
            DayTypeKey(day: calendar.startOfDay(for: $0.dayDate), type: normalize($0.mealName))
        }
        let logsByDayType = Dictionary(grouping: logs) {
            DayTypeKey(day: calendar.startOfDay(for: $0.dayDate), type: normalize($0.mealType.displayName))
        }

        // Per meal type, walk the 7 days and tally skips + time deltas.
        let mealTypes = Set(plannedByDayType.keys.map(\.type))
        for type in mealTypes.sorted() {
            var skipCount = 0
            var dayCount = 0
            var deltaMinutes: [Int] = []   // actual - planned, in minutes
            var onTimeCount = 0

            for (key, plannedItems) in plannedByDayType where key.type == type {
                dayCount += 1
                let plan = plannedItems.first!  // 1 planned meal per slot
                let logged = logsByDayType[key]?.first

                guard let logged else {
                    skipCount += 1
                    continue
                }

                if let plannedAt = scheduledDateTime(plan: plan, calendar: calendar) {
                    let actualMinutesOfDay = calendar.component(.hour, from: logged.loggedAt) * 60
                        + calendar.component(.minute, from: logged.loggedAt)
                    let plannedMinutesOfDay = calendar.component(.hour, from: plannedAt) * 60
                        + calendar.component(.minute, from: plannedAt)
                    let delta = actualMinutesOfDay - plannedMinutesOfDay
                    deltaMinutes.append(delta)
                    if abs(delta) <= 15 { onTimeCount += 1 }
                }
            }

            guard dayCount > 0 else { continue }

            // 1. Skips ≥3 of last 7 days for this meal.
            if skipCount >= 3 {
                out.append(.init(
                    subject: subject(forMealType: type),
                    text: "Often skips \(type) (skipped \(skipCount) of last \(dayCount) days)",
                    kind: .skip(type: type, count: skipCount, of: dayCount)
                ))
            }

            // 2. Consistent time drift in one direction, ≥30min, ≥4 days.
            if deltaMinutes.count >= 4 {
                let lateCount = deltaMinutes.filter { $0 >= 30 }.count
                let earlyCount = deltaMinutes.filter { $0 <= -30 }.count
                if lateCount >= 4 {
                    let avg = deltaMinutes.filter { $0 >= 30 }.reduce(0, +) / max(1, lateCount)
                    out.append(.init(
                        subject: subject(forMealType: type),
                        text: "Eats \(type) ~\(avg)min later than planned (\(lateCount) of \(dayCount) days)",
                        kind: .timeDrift(type: type, deltaMinutes: avg, direction: .later)
                    ))
                } else if earlyCount >= 4 {
                    let avg = abs(deltaMinutes.filter { $0 <= -30 }.reduce(0, +) / max(1, earlyCount))
                    out.append(.init(
                        subject: subject(forMealType: type),
                        text: "Eats \(type) ~\(avg)min earlier than planned (\(earlyCount) of \(dayCount) days)",
                        kind: .timeDrift(type: type, deltaMinutes: avg, direction: .earlier)
                    ))
                }
            }

            // 3. Reinforcement signal — meal hit within ±15min on ≥5 of 7 days.
            if onTimeCount >= 5 {
                out.append(.init(
                    subject: subject(forMealType: type),
                    text: "On-time \(type) (\(onTimeCount) of \(dayCount) days within 15min)",
                    kind: .reinforceOnTime(type: type, count: onTimeCount)
                ))
            }
        }

        return out
    }

    // MARK: - Apply (mutates context)

    static func apply(
        proposal: BehaviorProposal,
        existing: [LearnedPreference],
        in context: ModelContext,
        now: Date
    ) {
        // Find an existing pref for the same subject whose text is a close
        // match — same `kind` shape. We only reinforce a prior observation;
        // we don't replace user-stated prefs from an observation.
        let candidate = existing.first { pref in
            pref.subject == proposal.subject
                && matches(pref: pref, proposal: proposal)
        }

        if let candidate {
            // Reinforcement path — pref already exists.
            if candidate.userVerified || candidate.source == .explicit {
                // Don't touch user-stated prefs from an observation. Bump
                // evidence only when the behavior aligns.
                if case .reinforceOnTime = proposal.kind {
                    candidate.markReinforced(at: now)
                }
            } else {
                candidate.markReinforced(at: now)
            }
            return
        }

        // Insert path — only for skip/timeDrift; reinforceOnTime without an
        // existing pref produces nothing (we don't want to mint "on-time
        // dinner" prefs unprompted).
        switch proposal.kind {
        case .skip, .timeDrift:
            let new = LearnedPreference(
                text: proposal.text,
                subject: proposal.subject,
                confidence: 0.5,
                source: .observed,
                firstSeenAt: now,
                lastSeenAt: now
            )
            context.insert(new)
        case .reinforceOnTime:
            break
        }
    }

    // MARK: - Helpers

    static func fetchActivePreferences(in context: ModelContext) -> [LearnedPreference] {
        let desc = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { $0.isActive }
        )
        return (try? context.fetch(desc)) ?? []
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Map normalized meal type ("breakfast"/"lunch"/...) to canonical
    /// subject namespace. Unknown types fall back to a generic snack.
    static func subject(forMealType type: String) -> String {
        switch type {
        case "breakfast": LearnedPreferenceSubject.mealTimingBreakfast
        case "lunch": LearnedPreferenceSubject.mealTimingLunch
        case "dinner": LearnedPreferenceSubject.mealTimingDinner
        default: LearnedPreferenceSubject.mealTimingSnack
        }
    }

    private static func scheduledDateTime(plan: PlannedMeal, calendar: Calendar) -> Date? {
        // PlannedMeal.scheduledTime is "HH:mm" (24h). Combine with dayDate.
        let parts = plan.scheduledTime.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0...23).contains(h),
              (0...59).contains(m)
        else { return nil }
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: plan.dayDate)
    }

    /// Loose match: same subject + same proposal kind family. We're not
    /// doing string similarity — the kind enum is the source of truth.
    private static func matches(pref: LearnedPreference, proposal: BehaviorProposal) -> Bool {
        switch proposal.kind {
        case let .skip(type, _, _):
            return pref.text.localizedCaseInsensitiveContains("skips \(type)")
        case let .timeDrift(type, _, direction):
            let word = direction == .later ? "later" : "earlier"
            return pref.text.localizedCaseInsensitiveContains("\(type)")
                && pref.text.localizedCaseInsensitiveContains(word)
        case let .reinforceOnTime(type, _):
            return pref.text.localizedCaseInsensitiveContains(type)
        }
    }

    // MARK: - Types

    private struct DayTypeKey: Hashable {
        let day: Date
        let type: String
    }
}

/// Proposal emitted by `detectPatterns` and consumed by `apply`. Exposed
/// for tests; production callers go through `run(context:)`.
struct BehaviorProposal: Equatable {
    let subject: String
    let text: String
    let kind: Kind

    enum Kind: Equatable {
        case skip(type: String, count: Int, of: Int)
        case timeDrift(type: String, deltaMinutes: Int, direction: Direction)
        case reinforceOnTime(type: String, count: Int)
    }

    enum Direction: Equatable {
        case earlier
        case later
    }
}
