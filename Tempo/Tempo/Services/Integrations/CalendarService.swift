//
// CalendarService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import EventKit
import Foundation
import os

// MARK: - Calendar Service (Real Implementation)

// Per BUILD_PLAN step 13.1 — Real EventKit calendar integration.
// Per INTEGRATION_SPECS.md Section 4 — Authorization, fetching, categorization.
// Per ADR-013 — Apple Calendar via EventKit, singleton EKEventStore.

@Observable
final class CalendarService: CalendarServiceProtocol, @unchecked Sendable {
    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "app.tempo", category: "Calendar")

    private(set) var isAuthorized = false

    // MARK: - Cached Events

    private var cachedEvents: [CalendarEvent] = []
    private var lastFetchRange: DateInterval?

    init() {
        checkAuthorizationStatus()
        observeCalendarChanges()
    }

    // MARK: - Authorization

    // Per INTEGRATION_SPECS.md Section 4.1 — Use requestFullAccessToEvents() for iOS 17.4+.

    func requestAuthorization() async throws {
        let granted = try await eventStore.requestFullAccessToEvents()
        await MainActor.run {
            self.isAuthorized = granted
        }
        if granted {
            logger.info("Calendar access granted")
        } else {
            logger.warning("Calendar access denied by user")
        }
    }

    // MARK: - Authorization Check

    // Per INTEGRATION_SPECS.md Section 4.1 — Check on every app launch.

    private func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = (status == .fullAccess)
    }

    // MARK: - Fetch Events

    // Per INTEGRATION_SPECS.md Section 4.2 — Fetch and categorize calendar events.

    func fetchEvents(for dateRange: DateInterval) async throws -> [CalendarEvent] {
        guard isAuthorized else {
            return []
        }

        let predicate = eventStore.predicateForEvents(
            withStart: dateRange.start,
            end: dateRange.end,
            calendars: nil
        )

        let ekEvents = eventStore.events(matching: predicate)

        let events = ekEvents.map { event in
            CalendarEvent(
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                location: event.location
            )
        }

        cachedEvents = events
        lastFetchRange = dateRange
        return events
    }

    // MARK: - Football Detection

    // Per BUILD_PLAN step 13.1 — Events containing "football" or "calcio" in title.
    // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 6.5 — English + Italian keywords.

    func detectFootballDays(in range: DateInterval) -> [Date] {
        let calendar = Calendar.current
        return Array(Set(
            detectFootballEvents(in: range)
                .map { calendar.startOfDay(for: $0.startDate) }
        )).sorted()
    }

    func detectFootballEvents(in range: DateInterval) -> [CalendarEvent] {
        eventsInRange(range)
            .filter { isFootballEvent($0) }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Exam Detection

    // Per BUILD_PLAN step 13.1 — Events containing "exam" or "esame" recognized.

    func detectExamDates(in range: DateInterval) -> [CalendarExam] {
        let relevant = eventsInRange(range)

        return relevant
            .filter { isExamEvent($0) }
            .map { event in
                CalendarExam(
                    subject: extractSubject(from: event.title),
                    date: event.startDate,
                    durationMinutes: Int(event.endDate.timeIntervalSince(event.startDate) / 60)
                )
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Exam Persistence

    /// Persist an exam-tagged event to the user's default calendar so the
    /// detectExamDates query picks it up on the next refresh.
    func addExam(name: String, date: Date) async throws -> Bool {
        if !isAuthorized {
            try await requestAuthorization()
        }
        guard isAuthorized, let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
            return false
        }
        let event = EKEvent(eventStore: eventStore)
        // Title prefixed with "Exam:" so isExamEvent classifies it on read-back.
        event.title = "Exam: \(name)"
        event.calendar = defaultCalendar

        // Anchor to the noon hour of the chosen day; users picking a date
        // typically don't supply a time, and noon avoids day-boundary surprises.
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        event.startDate = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? date
        event.endDate = event.startDate.addingTimeInterval(2 * 3600)

        try eventStore.save(event, span: .thisEvent)
        // Invalidate cache so detectExamDates re-reads.
        cachedEvents = []
        lastFetchRange = nil
        return true
    }

    // MARK: - Workout Window Suggestion

    // Per build done_when #15 — largest free contiguous block of >= 45 min in
    // the 08:00–22:00 waking window. All-day events are ignored (they don't
    // block a real time slot). Requests access lazily on first use.

    func suggestWorkoutWindow(for date: Date, preferring preference: TrainingTimePreference = .anyFree) async -> DateInterval? {
        if !isAuthorized {
            try? await requestAuthorization()
        }
        guard isAuthorized else {
            return nil
        }

        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        guard
            let windowStart = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day),
            let windowEnd = cal.date(bySettingHour: 22, minute: 0, second: 0, of: day),
            windowEnd > windowStart
        else {
            return nil
        }

        let minimumDuration: TimeInterval = 45 * 60
        let dayRange = DateInterval(start: windowStart, end: windowEnd)
        let events = (try? await fetchEvents(for: dayRange)) ?? []

        // Busy intervals: timed events only, clamped to the waking window,
        // sorted and merged so overlapping meetings collapse into one block.
        let busy = events
            .filter { !$0.isAllDay && $0.endDate > windowStart && $0.startDate < windowEnd }
            .map { event in
                DateInterval(
                    start: max(event.startDate, windowStart),
                    end: min(event.endDate, windowEnd)
                )
            }
            .sorted { $0.start < $1.start }

        var merged: [DateInterval] = []
        for interval in busy {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }

        // Collect ALL free gaps between merged busy blocks (not just the largest)
        // so the training-time preference can pick among them.
        var freeGaps: [DateInterval] = []
        var cursor = windowStart
        for block in merged {
            if block.start > cursor {
                freeGaps.append(DateInterval(start: cursor, end: block.start))
            }
            cursor = max(cursor, block.end)
        }
        // Trailing gap after the last busy block to the window end.
        if cursor < windowEnd {
            freeGaps.append(DateInterval(start: cursor, end: windowEnd))
        }

        let daypart = Self.preferredDaypart(for: preference, on: day, calendar: cal)
        return Self.bestWindow(freeGaps: freeGaps, preferred: daypart, minimumDuration: minimumDuration)
    }

    /// The waking-hours sub-window matching the user's training-time preference,
    /// or nil for `.anyFree` (no time-of-day bias — the launch behavior).
    /// Requirement (c): "correct real timings based on onboarding preferences."
    static func preferredDaypart(for preference: TrainingTimePreference, on day: Date, calendar cal: Calendar) -> DateInterval? {
        let hours: (start: Int, end: Int)
        switch preference {
        case .morning: hours = (8, 12)
        case .midday: hours = (12, 17)
        case .evening: hours = (17, 22)
        case .anyFree: return nil
        }
        guard let start = cal.date(bySettingHour: hours.start, minute: 0, second: 0, of: day),
              let end = cal.date(bySettingHour: hours.end, minute: 0, second: 0, of: day),
              end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Pick the workout window: prefer a free slot (≥ minimum) that falls inside
    /// the user's preferred daypart, choosing the LONGEST such overlap; if none
    /// qualifies (that daypart is fully busy, or `.anyFree`), fall back to the
    /// largest free gap overall — so the result is ALWAYS a real, calendar-free
    /// slot, just biased toward the preference when the calendar allows.
    static func bestWindow(freeGaps: [DateInterval], preferred: DateInterval?, minimumDuration: TimeInterval) -> DateInterval? {
        if let preferred {
            let inPreferred = freeGaps
                .compactMap { $0.intersection(with: preferred) }
                .filter { $0.duration >= minimumDuration }
            if let best = inPreferred.max(by: { $0.duration < $1.duration }) {
                return best
            }
        }
        return freeGaps
            .filter { $0.duration >= minimumDuration }
            .max(by: { $0.duration < $1.duration })
    }

    // MARK: - Saved Workout Event Lookup

    // Drives the live countdown banner. Matches the title convention written
    // by WorkoutEventEditView ("<Type> Workout"). Only returns an event whose
    // start is still in the future so a finished/ongoing session clears the
    // banner.

    func todaysWorkoutEvent(for date: Date, matchingID: String?) async -> DateInterval? {
        if !isAuthorized {
            try? await requestAuthorization()
        }
        guard isAuthorized else {
            return nil
        }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else {
            return nil
        }
        let now = Date()

        // 1. ID-first: resolve the exact event we created. Survives the user
        //    renaming it in Calendar.app. event(withIdentifier:) returns nil
        //    if the user deleted it or its calendar was removed — then we
        //    fall through to the heuristic.
        if let id = matchingID, let ev = eventStore.event(withIdentifier: id) {
            let valid = !ev.isAllDay
                && ev.startDate > now
                && ev.startDate >= dayStart
                && ev.startDate < dayEnd
            if valid {
                return DateInterval(start: ev.startDate, end: ev.endDate)
            }
        }

        // 2. Heuristic fallback: title ends with "Workout". Covers
        //    manually-created events and events saved before ID persistence
        //    existed.
        let events = (try? await fetchEvents(for: DateInterval(start: dayStart, end: dayEnd))) ?? []
        return events
            .filter { !$0.isAllDay && $0.title.hasSuffix("Workout") && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
    }

    // MARK: - Class Detection

    func detectClassSchedule(for date: Date) -> [CalendarClass] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let range = DateInterval(start: startOfDay, end: endOfDay)
        let relevant = eventsInRange(range)

        return relevant
            .filter { isClassEvent($0) && !$0.isAllDay }
            .map { event in
                CalendarClass(
                    subject: event.title,
                    startTime: event.startDate,
                    endTime: event.endDate,
                    location: nil
                )
            }
            .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Event Categorization

    // Per INTEGRATION_SPECS.md Section 4.2 — Keyword-based categorization.
    // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 6.5 — Dual-language (English + Italian).

    private func isFootballEvent(_ event: CalendarEvent) -> Bool {
        let keywords = [
            "football", "soccer", "calcio", "calcetto",
            "partita", "match", "game", "practice",
            "allenamento",
        ]
        return matchesAnyKeyword(event.title, keywords: keywords)
    }

    private func isExamEvent(_ event: CalendarEvent) -> Bool {
        let keywords = [
            "exam", "esame", "test", "final", "midterm",
            "partial", "parziale", "appello", "prova",
            "quiz", "assessment",
        ]
        return matchesAnyKeyword(event.title, keywords: keywords)
    }

    private func isClassEvent(_ event: CalendarEvent) -> Bool {
        let keywords = [
            "class", "lecture", "lezione", "lab",
            "laboratorio", "seminar", "seminario",
            "tutorial", "lesson", "corso",
        ]
        return matchesAnyKeyword(event.title, keywords: keywords)
    }

    private func matchesAnyKeyword(_ title: String, keywords: [String]) -> Bool {
        let lowered = title.lowercased()
        return keywords.contains { lowered.contains($0) }
    }

    /// Extract a subject name from an event title by removing keyword tokens.
    private func extractSubject(from title: String) -> String {
        let removeWords = [
            "exam", "esame", "test", "final", "midterm",
            "partial", "parziale", "appello", "prova", "quiz",
            "-", ":", "–",
        ]
        var result = title
        for word in removeWords {
            result = result.replacingOccurrences(
                of: word,
                with: "",
                options: [.caseInsensitive]
            )
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    // MARK: - Helpers

    private func eventsInRange(_ range: DateInterval) -> [CalendarEvent] {
        // Use cached events if available and overlapping
        if let cached = lastFetchRange,
           cached.start <= range.start, cached.end >= range.end
        {
            return cachedEvents.filter {
                $0.startDate >= range.start && $0.startDate < range.end
            }
        }

        // Otherwise fetch fresh
        guard isAuthorized else {
            return []
        }

        let predicate = eventStore.predicateForEvents(
            withStart: range.start,
            end: range.end,
            calendars: nil
        )

        return eventStore.events(matching: predicate).map { event in
            CalendarEvent(
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                location: event.location
            )
        }
    }

    // MARK: - Change Observation

    // Per INTEGRATION_SPECS.md Section 4.4 — Observe EKEventStoreChanged.

    private func observeCalendarChanges() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("Calendar store changed, invalidating cache")
            self?.cachedEvents = []
            self?.lastFetchRange = nil
        }
    }
}
