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
                calendarName: event.calendar.title
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
        let relevant = eventsInRange(range)

        return Array(Set(
            relevant
                .filter { isFootballEvent($0) }
                .map { calendar.startOfDay(for: $0.startDate) }
        )).sorted()
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
                calendarName: event.calendar.title
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
