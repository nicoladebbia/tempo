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
}

// MARK: - CalendarEvent

struct CalendarEvent {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String?
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
