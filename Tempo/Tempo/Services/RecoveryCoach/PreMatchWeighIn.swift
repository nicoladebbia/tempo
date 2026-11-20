//
// PreMatchWeighIn.swift
// Tempo
//
// "Weigh yourself now, before you drink": a local reminder 60 minutes before a
// scheduled football session. The date maths is a pure function
// (`PreMatchWeighInPlan`); `PreMatchWeighInScheduler` reads the schedule,
// checks Health for a recent weight and (re)schedules. Called on app
// foreground and when the schedule changes. Rebuild-from-scratch, so there are
// never duplicates.
//
// Where a football session's time lives: a dated `Match.kickoff`, or a
// football `TimeBlock` in the day plan (from the calendar). The recurring
// "football days" setting has no clock time, so it can't schedule one.
//

import Foundation
import os
import SwiftData
import UserNotifications

// MARK: - Pure plan

enum PreMatchWeighInPlan {
    static let idPrefix = "prematch.weighin."
    static let leadTime: TimeInterval = 60 * 60
    static let horizon: TimeInterval = 7 * 24 * 3600
    /// A weight this recent before the reminder makes it pointless.
    static let alreadyWeighedWithin: TimeInterval = 90 * 60
    /// Two kickoffs closer than this are one session listed twice.
    static let sameSessionWithin: TimeInterval = 30 * 60

    struct Reminder: Equatable {
        let kickoff: Date
        let fireDate: Date

        var identifier: String { "\(PreMatchWeighInPlan.idPrefix)\(Int(kickoff.timeIntervalSince1970))" }
    }

    /// Reminders for kickoffs whose reminder time falls in (now, now + 7 days].
    /// `lastWeighIn`: the newest weight we know about; a reminder is dropped when
    /// that weight was taken in the 90 minutes before the reminder would fire
    /// (or any time after it, which also covers "already weighed in").
    static func reminders(kickoffs: [Date], now: Date, lastWeighIn: Date?) -> [Reminder] {
        var unique: [Date] = []
        for kickoff in kickoffs.sorted() {
            if let last = unique.last, kickoff.timeIntervalSince(last) < sameSessionWithin { continue }
            unique.append(kickoff)
        }
        return unique.compactMap { kickoff in
            let fire = kickoff.addingTimeInterval(-leadTime)
            guard fire > now, fire <= now.addingTimeInterval(horizon) else { return nil }
            if let lastWeighIn, lastWeighIn >= fire.addingTimeInterval(-alreadyWeighedWithin) { return nil }
            return Reminder(kickoff: kickoff, fireDate: fire)
        }
    }

    /// Kickoffs from dated matches plus football blocks of the day plans.
    static func kickoffs(
        matchKickoffs: [Date], footballBlocks: [(day: Date, startMinuteOfDay: Int)], calendar: Calendar = .current
    ) -> [Date] {
        let fromBlocks = footballBlocks.compactMap { block in
            calendar.date(byAdding: .minute, value: block.startMinuteOfDay, to: calendar.startOfDay(for: block.day))
        }
        return matchKickoffs + fromBlocks
    }
}

// MARK: - Scheduler

@MainActor
enum PreMatchWeighInScheduler {
    static let idPrefix = PreMatchWeighInPlan.idPrefix
    private static let logger = Logger(subsystem: "app.tempo", category: "pre-match-weighin")
    private static var latest: Task<Void, Never>?

    /// Serialised: each call waits for the earlier one.
    static func reschedule(
        modelContext: ModelContext, healthKit: (any HealthKitServiceProtocol)?,
        store: RecoveryCoachStore = .shared, now: Date = Date()
    ) {
        let previous = latest
        latest = Task { @MainActor in
            await previous?.value
            await rebuild(modelContext: modelContext, healthKit: healthKit, store: store, now: now)
        }
    }

    static func rebuild(
        modelContext: ModelContext, healthKit: (any HealthKitServiceProtocol)?,
        store: RecoveryCoachStore = .shared, now: Date = Date()
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard store.read().preMatchReminderOn else { return }

        let horizon = now.addingTimeInterval(PreMatchWeighInPlan.horizon + PreMatchWeighInPlan.leadTime)
        let kickoffs = PreMatchWeighInPlan.kickoffs(
            matchKickoffs: matchKickoffs(in: modelContext, from: now, to: horizon),
            footballBlocks: footballBlocks(in: modelContext, from: now, to: horizon)
        )
        let lastWeighIn = await latestWeighIn(healthKit: healthKit, store: store, now: now)
        for reminder in PreMatchWeighInPlan.reminders(kickoffs: kickoffs, now: now, lastWeighIn: lastWeighIn) {
            let content = UNMutableNotificationContent()
            content.title = "Weigh yourself now"
            content.body = "Before you drink. It takes a minute and makes your recovery numbers real."
            content.categoryIdentifier = CoachNotifications.preCategoryID
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: reminder.identifier, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                logger.error("pre-match reminder not scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func matchKickoffs(in context: ModelContext, from: Date, to: Date) -> [Date] {
        let descriptor = FetchDescriptor<Match>(predicate: #Predicate<Match> { $0.kickoff >= from && $0.kickoff <= to })
        do {
            return try context.fetch(descriptor).map(\.kickoff)
        } catch {
            logger.error("matches not read: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func footballBlocks(in context: ModelContext, from: Date, to: Date) -> [(day: Date, startMinuteOfDay: Int)] {
        let lower = Calendar.current.startOfDay(for: from)
        let descriptor = FetchDescriptor<DayPlan>(predicate: #Predicate<DayPlan> { $0.date >= lower && $0.date <= to })
        do {
            return try context.fetch(descriptor).flatMap { plan in
                plan.blocks.filter { $0.kind == .football }.map { (day: plan.date, startMinuteOfDay: $0.startMinuteOfDay) }
            }
        } catch {
            logger.error("day plans not read: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The newest weight in the last 4 hours (Health + manual), or nil.
    private static func latestWeighIn(
        healthKit: (any HealthKitServiceProtocol)?, store: RecoveryCoachStore, now: Date
    ) async -> Date? {
        var newest = store.read().manualWeighIns.map(\.time).filter { $0 <= now }.max()
        if let healthKit {
            do {
                let samples = try await healthKit.fetchBodyMassSamples(from: now.addingTimeInterval(-4 * 3600), to: now)
                if let health = samples.map(\.time).max(), health > (newest ?? .distantPast) { newest = health }
            } catch {
                logger.error("recent weight not read: \(error.localizedDescription, privacy: .public)")
            }
        }
        return newest
    }
}
