import Foundation

extension Date {

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self) ?? self
    }

    /// ISO format: "2026-03-25"
    var dateString: String {
        TempoDateFormatters.isoDate.string(from: self)
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: self) ?? self
    }

    func adding(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: self) ?? self
    }

    /// Days between two dates (absolute value).
    func daysBetween(_ other: Date) -> Int {
        abs(Calendar.current.dateComponents([.day], from: startOfDay, to: other.startOfDay).day ?? 0)
    }

    /// "5 min ago", "2 hours ago", "Yesterday"
    var timeAgo: String {
        TempoDateFormatters.relative.localizedString(for: self, relativeTo: Date())
    }
}
