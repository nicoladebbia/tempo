//
// MealTimeHints.swift
// Tempo
//
// Pulls "when did I eat this" out of a Quick Log sentence without asking the
// model: "at 1pm", "at 13:30", "for lunch", "yesterday dinner", "this
// morning". The model's own meal_type / eaten_at stay as a fallback; whatever
// is found here wins because it is deterministic and unit-tested.
//

import Foundation

struct MealTimeHints: Equatable {
    /// Wall-clock eat time, or nil when the text names none (callers use now).
    var date: Date?
    var mealType: MealType?

    static let none = MealTimeHints(date: nil, mealType: nil)

    /// Typical clock time for a meal when the user only named the meal and a
    /// different day ("yesterday dinner").
    static func typicalTime(for type: MealType) -> (hour: Int, minute: Int) {
        switch type {
        case .breakfast: (hour: 8, minute: 0)
        case .lunch: (hour: 13, minute: 0)
        case .dinner: (hour: 20, minute: 0)
        case .snack: (hour: 16, minute: 0)
        }
    }

    // MARK: - Parse

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> MealTimeHints {
        let lower = text.lowercased()
        let type = mealType(in: lower)
        let dayOffset = dayOffset(in: lower)
        let clock = explicitClock(in: lower, mealType: type, now: now, calendar: calendar, dayOffset: dayOffset)

        guard clock != nil || dayOffset != 0 else {
            return MealTimeHints(date: nil, mealType: type)
        }

        let day = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        if let clock {
            parts.hour = clock.hour
            parts.minute = clock.minute
        } else {
            // "yesterday dinner": the meal's usual time. "yesterday" alone: noon-ish.
            let typical: (hour: Int, minute: Int) = type.map(typicalTime(for:)) ?? (hour: 12, minute: 0)
            parts.hour = typical.hour
            parts.minute = typical.minute
        }
        // A time that hasn't happened yet today means "just now", not the future.
        var date = calendar.date(from: parts)
        if let candidate = date, candidate > now {
            date = now
        }
        return MealTimeHints(date: date, mealType: type)
    }

    // MARK: - Pieces

    private static func mealType(in lower: String) -> MealType? {
        // "breakfast burrito for dinner": the meal word after "for"/"as"/"at"
        // names the meal; a dish name before it doesn't.
        let named = #"\b(?:for|as|at)\s+(?:my\s+|a\s+|an\s+|the\s+)?(breakfast|lunch|dinner|supper|snack)\b"#
        if let match = lower.range(of: named, options: .regularExpression) {
            let word = lower[match].split(separator: " ").last.map(String.init) ?? ""
            switch word {
            case "breakfast": return .breakfast
            case "lunch": return .lunch
            case "dinner", "supper": return .dinner
            case "snack": return .snack
            default: break
            }
        }
        // Earliest mention wins ("lunch ... then a dinner snack" is rare).
        let candidates: [(String, MealType)] = [
            ("breakfast", .breakfast), ("this morning", .breakfast),
            ("lunch", .lunch),
            ("dinner", .dinner), ("supper", .dinner), ("last night", .dinner), ("tonight", .dinner),
            ("snack", .snack),
        ]
        return candidates
            .compactMap { word, type in lower.range(of: word).map { ($0.lowerBound, type) } }
            .min { $0.0 < $1.0 }?.1
    }

    private static func dayOffset(in lower: String) -> Int {
        if lower.contains("yesterday") {
            return -1
        }
        if lower.contains("last night") {
            // "last night at 1am" is today's small hours; the evening is yesterday.
            return lower.range(of: #"last night.{0,6}\b(?:at\s+)?(?:12|1|2|3|4)\s*(?:am|a\.m\.)"#, options: .regularExpression) == nil ? -1 : 0
        }
        return 0
    }

    /// "at 1pm", "at 1:30 pm", "at 13:30", "1pm". Bare "at 8" is resolved
    /// from the meal type (dinner at 8 → 20:00) or the most recent past
    /// occurrence of that hour.
    private static func explicitClock(
        in lower: String,
        mealType: MealType?,
        now: Date,
        calendar: Calendar,
        dayOffset: Int
    ) -> (hour: Int, minute: Int)? {
        let pattern = #"(?<![\w:.])(?:at\s+|around\s+|@\s*)?(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?(?![\w:])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(lower.startIndex..., in: lower)
        for match in regex.matches(in: lower, range: range) {
            guard let hourRange = Range(match.range(at: 1), in: lower), var hour = Int(lower[hourRange]) else {
                continue
            }
            let whole = Range(match.range, in: lower).map { String(lower[$0]) } ?? ""
            let minute = Range(match.range(at: 2), in: lower).flatMap { Int(lower[$0]) } ?? 0
            let meridiem = Range(match.range(at: 3), in: lower).map { String(lower[$0]).replacingOccurrences(of: ".", with: "") }
            let hasPrefix = whole.hasPrefix("at") || whole.hasPrefix("around") || whole.hasPrefix("@")
            let hasMinutes = match.range(at: 2).location != NSNotFound
            // A bare number is only a time with "at", a colon, or am/pm.
            guard hasPrefix || hasMinutes || meridiem != nil, minute < 60 else {
                continue
            }
            // "around 3 eggs": a bare number followed by a word is a quantity, not a time.
            if meridiem == nil, !hasMinutes, let end = Range(match.range, in: lower)?.upperBound,
               lower[end...].drop(while: { $0 == " " }).first?.isLetter == true
            {
                continue
            }
            if let meridiem {
                guard (1 ... 12).contains(hour) else {
                    continue
                }
                if meridiem == "pm", hour < 12 {
                    hour += 12
                }
                if meridiem == "am", hour == 12 {
                    hour = 0
                }
                return (hour, minute)
            }
            guard (0 ... 23).contains(hour) else {
                continue
            }
            if hour > 12 || hour == 0 {
                return (hour, minute)
            }
            let resolved = resolveAmbiguous(
                hour: hour, minute: minute, mealType: mealType, now: now, calendar: calendar, dayOffset: dayOffset
            )
            return (resolved, minute)
        }
        return nil
    }

    /// 1…12 with no am/pm.
    private static func resolveAmbiguous(
        hour: Int,
        minute: Int,
        mealType: MealType?,
        now: Date,
        calendar: Calendar,
        dayOffset: Int
    ) -> Int {
        switch mealType {
        case .dinner? where hour < 12: return hour + 12
        case .lunch? where hour < 6: return hour + 12
        case .lunch? where hour <= 12: return hour
        case .dinner? where hour == 12, .snack? where hour == 12: return 12
        case .snack? where hour < 6: return hour + 12
        case .breakfast?: return hour
        default: break
        }
        guard dayOffset == 0 else {
            return hour
        }
        // No meal hint: the most recent occurrence of that hour that isn't in the future.
        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let pm = (hour % 12 + 12) * 60 + minute
        let am = (hour % 12) * 60 + minute
        if pm <= nowMinutes {
            return hour % 12 + 12
        }
        if am <= nowMinutes {
            return hour % 12
        }
        return hour % 12 + 12 // in the future either way: assume the evening reading
    }
}
