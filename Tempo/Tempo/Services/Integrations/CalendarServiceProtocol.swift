import Foundation

// MARK: - Protocol

protocol CalendarServiceProtocol: Sendable {
    func requestAuthorization() async throws
    func fetchEvents(for dateRange: DateInterval) async throws -> [CalendarEvent]
    func detectFootballDays(in range: DateInterval) -> [Date]
    func detectExamDates(in range: DateInterval) -> [CalendarExam]
    func detectClassSchedule(for date: Date) -> [CalendarClass]
}

// MARK: - Data Types (plain structs — no EventKit dependency)

struct CalendarEvent: Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String?
}

struct CalendarExam: Sendable {
    let subject: String
    let date: Date
    let durationMinutes: Int
}

struct CalendarClass: Sendable {
    let subject: String
    let startTime: Date
    let endTime: Date
    let location: String?
}
