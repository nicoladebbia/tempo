//
// CalendarServiceProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - CalendarServiceProtocol

protocol CalendarServiceProtocol: Sendable {
    func requestAuthorization() async throws
    func fetchEvents(for dateRange: DateInterval) async throws -> [CalendarEvent]
    func detectFootballDays(in range: DateInterval) -> [Date]
    func detectExamDates(in range: DateInterval) -> [CalendarExam]
    func detectClassSchedule(for date: Date) -> [CalendarClass]
    /// Persist an exam-tagged event to the user's default calendar.
    /// Returns false if calendar access is denied or the event cannot be saved.
    func addExam(name: String, date: Date) async throws -> Bool

    /// Largest free contiguous block of >= 45 minutes within the waking
    /// window (08:00-22:00) of the given day, derived from the user's
    /// calendar events. Returns nil if no qualifying gap exists or access
    /// is denied. Requests calendar access lazily on first use.
    func suggestWorkoutWindow(for date: Date) async -> DateInterval?

    /// The user's saved workout event for `date` whose start is still in
    /// the future. Drives the live countdown banner. Resolution order:
    /// 1. If `matchingID` resolves to a real event today with a future
    ///    start, use it (robust — survives the user renaming the event).
    /// 2. Otherwise fall back to the title heuristic (title ends with
    ///    "Workout"), so manually-created or pre-persistence events still
    ///    bind.
    /// Returns nil if none / already started / access denied.
    func todaysWorkoutEvent(for date: Date, matchingID: String?) async -> DateInterval?
}

// MARK: - CalendarEvent

struct CalendarEvent {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String?
    /// EKEvent.location — used by meal-timing to decide whether a
    /// conflicting event forces a "portable only" meal. nil / empty /
    /// containing "home" means the user can cook through it.
    var location: String? = nil
}

// MARK: - CalendarExam

struct CalendarExam {
    let subject: String
    let date: Date
    let durationMinutes: Int
}

// MARK: - CalendarClass

struct CalendarClass {
    let subject: String
    let startTime: Date
    let endTime: Date
    let location: String?
}
