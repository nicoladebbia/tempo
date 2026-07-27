//
// MockCalendarService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

final class MockCalendarService: CalendarServiceProtocol, @unchecked Sendable {
    func requestAuthorization() async throws {
        // No-op in mock
    }

    func fetchEvents(for dateRange: DateInterval) async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = dateRange.start
        var events: [CalendarEvent] = []

        for dayOffset in 0 ..< 7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: day)

            // Classes MWF 9-12
            if [2, 4, 6].contains(weekday) {
                if let classStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                   let classEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
                {
                    events.append(CalendarEvent(
                        title: "Computer Science",
                        startDate: classStart,
                        endDate: classEnd,
                        isAllDay: false,
                        calendarName: "University"
                    ))
                }
            }

            // Football Tue/Thu 18:00-20:00
            if [3, 5].contains(weekday) {
                if let fbStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day),
                   let fbEnd = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day)
                {
                    events.append(CalendarEvent(
                        title: "Football Training",
                        startDate: fbStart,
                        endDate: fbEnd,
                        isAllDay: false,
                        calendarName: "Sport"
                    ))
                }
            }
        }

        return events
    }

    func detectFootballDays(in range: DateInterval) -> [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var current = range.start

        while current <= range.end {
            let weekday = calendar.component(.weekday, from: current)
            if [3, 5].contains(weekday) { // Tue, Thu
                dates.append(calendar.startOfDay(for: current))
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? range.end
        }

        return dates
    }

    func detectExamDates(in range: DateInterval) -> [CalendarExam] {
        let calendar = Calendar.current
        guard let examDate = calendar.date(byAdding: .day, value: 14, to: Date()) else {
            return []
        }
        return [
            CalendarExam(subject: "Algorithms & Data Structures", date: examDate, durationMinutes: 120),
        ]
    }

    func addExam(name: String, date: Date) async throws -> Bool {
        // Mock acknowledges the call without persisting.
        true
    }

    func suggestWorkoutWindow(for date: Date, preferring _: TrainingTimePreference = .anyFree) async -> DateInterval? {
        // Mock returns a fixed afternoon block so previews/tests are stable.
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        guard
            let start = cal.date(bySettingHour: 14, minute: 0, second: 0, of: day),
            let end = cal.date(bySettingHour: 15, minute: 30, second: 0, of: day)
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    func todaysWorkoutEvent(for _: Date, matchingID _: String?) async -> DateInterval? {
        // Mock has no saved event by default (suggestion mode in previews).
        nil
    }

    func detectClassSchedule(for date: Date) -> [CalendarClass] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)

        guard [2, 4, 6].contains(weekday) else {
            return []
        }

        guard let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date),
              let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)
        else {
            return []
        }

        return [
            CalendarClass(subject: "Computer Science", startTime: start, endTime: end, location: "Building A, Room 201"),
        ]
    }
}
