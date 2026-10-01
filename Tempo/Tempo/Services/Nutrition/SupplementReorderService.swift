//
// SupplementReorderService.swift
// Tempo
//
// "When to buy/reorder" — the other half of the supplements feature (timing
// is `SupplementScheduleEngine`). Pure logic over `Supplement` +
// `SupplementIntakeLog`: how many servings are left, whether that's low
// enough to warn about, and what marking a dose taken/undone/restocked does
// to the count. No SwiftData fetch/save here — callers (the view model, the
// notification delegate, the reorder sheet) own the ModelContext and persist.
//

import Foundation

enum SupplementReorderService {
    /// Days of history the intake rate is estimated from.
    static let intakeWindowDays = 14
    /// At or below this many days left, the shelf shows the low-stock banner
    /// and (once per restock cycle) a reminder fires.
    static let lowStockThresholdDays = 7

    /// First day of the intake window — start of day, so a log written this
    /// morning N days ago isn't cut off by the current time of day.
    static func intakeWindowStart(asOf: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: asOf)
        return calendar.date(byAdding: .day, value: -intakeWindowDays, to: today) ?? today
    }

    /// True when the user has entered ANY quantity info for this supplement —
    /// only tracked items get a days-left estimate or a decrement on "taken".
    static func isTracked(_ supplement: Supplement) -> Bool {
        supplement.servingsRemaining > 0 || supplement.servingsPerContainer != nil
    }

    /// Estimated days of supply left, from the last `intakeWindowDays` days of
    /// intake logs. nil when there's no reliable signal to estimate from:
    /// untracked items, or a conditional (non-`takeDaily`) item with zero
    /// logged intake in the window (we don't know its real cadence yet).
    static func daysLeft(
        for supplement: Supplement,
        recentLogs: [SupplementIntakeLog],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        guard isTracked(supplement) else {
            return nil
        }
        let remaining = supplement.servingsRemaining
        guard remaining > 0 else {
            return 0
        }

        let today = calendar.startOfDay(for: asOf)
        let windowStart = calendar.date(byAdding: .day, value: -intakeWindowDays, to: today) ?? today
        let matchingDays = Set(
            recentLogs
                .filter {
                    $0.day >= windowStart && $0.day <= today
                        && ($0.supplementID.map { $0 == supplement.id } ?? ($0.supplementName == supplement.name))
                }
                .map { calendar.startOfDay(for: $0.day) }
        ).count
        let windowDays = max(1, (calendar.dateComponents([.day], from: windowStart, to: today).day ?? 0) + 1)
        // A supplement added 3 days ago has only 3 days of history: dividing
        // by the full window would understate its rate and overstate its supply.
        let createdDay = calendar.startOfDay(for: supplement.createdAt)
        let daysSinceCreated = max(1, (calendar.dateComponents([.day], from: createdDay, to: today).day ?? 0) + 1)
        let observedDays = min(windowDays, daysSinceCreated)

        let perDay: Double
        if matchingDays > 0 {
            perDay = min(1.0, Double(matchingDays) / Double(observedDays))
        } else if supplement.takeDaily {
            // Fallback for a brand-new daily supplement with no logged history yet.
            perDay = 1.0
        } else {
            return nil
        }
        guard perDay > 0 else {
            return nil
        }
        return Int((remaining / perDay).rounded(.down))
    }

    /// True when the shelf should surface the low-stock banner for this item.
    static func needsReorder(
        for supplement: Supplement,
        recentLogs: [SupplementIntakeLog],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let left = daysLeft(for: supplement, recentLogs: recentLogs, asOf: asOf, calendar: calendar) else {
            // Untracked, or a conditional (non-daily) item with no logged
            // intake: no rate to estimate from, and a serving count alone says
            // nothing about how long a "when needed" item lasts. Don't flag.
            return false
        }
        return left <= lowStockThresholdDays
    }

    /// True when a low-stock alert hasn't fired yet for the CURRENT restock
    /// cycle — a restock more recent than the last alert starts a fresh cycle
    /// without needing to clear `lastReorderAlertAt`.
    static func shouldSendReorderAlert(
        for supplement: Supplement,
        recentLogs: [SupplementIntakeLog],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard needsReorder(for: supplement, recentLogs: recentLogs, asOf: asOf, calendar: calendar) else {
            return false
        }
        guard let alertedAt = supplement.lastReorderAlertAt else {
            return true
        }
        if let restockedAt = supplement.lastRestockedAt, restockedAt > alertedAt {
            return true
        }
        return false
    }

    // MARK: - Mutations (caller saves the context)

    /// "I took it" — decrements by one serving when tracked. Clamped at 0;
    /// untracked items (no quantity ever entered) are left untouched.
    /// Returns the amount actually taken off (0 when untracked or already
    /// empty, less than 1 when clamped) so an undo can give back exactly that.
    @discardableResult
    static func applyTaken(to supplement: Supplement) -> Double {
        guard isTracked(supplement) else {
            return 0
        }
        let before = supplement.servingsRemaining
        supplement.servingsRemaining = max(0, before - 1)
        return before - supplement.servingsRemaining
    }

    /// Undo — adds back `amount`, what `applyTaken` actually removed. nil is a
    /// log from before that was recorded: one serving, tracked items only.
    /// Not capped at a container: after a restock the leftovers plus the new
    /// tub can exceed one. Callers only undo a day that has a taken log, so it
    /// can't run twice.
    static func applyUndo(to supplement: Supplement, amount: Double? = nil) {
        if let amount {
            if amount > 0 {
                supplement.servingsRemaining += amount
            }
        } else if isTracked(supplement) {
            supplement.servingsRemaining += 1
        }
    }

    /// "Restocked" — adds a new container to what's left (same math as a
    /// barcode rescan, `Supplement.restock(fromContainerSize:)`) and starts a
    /// new reorder cycle. Returns `false` and changes NOTHING when the
    /// container size is unknown: adding zero servings while still stamping a
    /// new cycle left the item "running low" and re-armed the alert to fire
    /// again straight away.
    @discardableResult
    static func restock(_ supplement: Supplement, at date: Date = Date()) -> Bool {
        guard let full = supplement.servingsPerContainer, full > 0 else {
            return false
        }
        supplement.servingsRemaining += full
        supplement.lastRestockedAt = date
        supplement.updatedAt = date
        return true
    }
}
