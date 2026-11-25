import Fluent
import Foundation
import Vapor

// MARK: - ArenaService

//
// Shared rules for the Arena routes: what "friends" means, which days make up
// a week, and how daily rows add up to scores. Kept free of routing so the
// friend, leaderboard and challenge controllers agree on one answer.

enum ArenaService {
    // MARK: Days and weeks

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .iso8601) // weeks start on Monday
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// "YYYY-MM-DD" for a moment, in UTC (the server's own notion of "today").
    static func dayString(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parseDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-")
        guard parts.count == 3, string.count == 10,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        guard let date = utc.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        // Reject 2026-02-31 style overflow: the round trip must match.
        return dayString(date) == string ? date : nil
    }

    static func addDays(_ days: Int, to day: String) -> String? {
        guard let date = parseDay(day), let moved = utc.date(byAdding: .day, value: days, to: date) else { return nil }
        return dayString(moved)
    }

    /// The Monday-to-Sunday week a leaderboard covers. `requestedStart` is what
    /// the app asks for (its own current ISO week); anything unusable falls
    /// back to the server's current week.
    static func week(containing now: Date, requestedStart: String?) -> (start: String, end: String) {
        var anchor = now
        if let requestedStart, let date = parseDay(requestedStart), abs(date.timeIntervalSince(now)) < 10 * 86400 {
            anchor = date
        }
        let monday = utc.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
        let start = dayString(monday)
        return (start, addDays(6, to: start) ?? start)
    }

    // MARK: Friends

    /// What other people see of a user: the display name, or "Friend" when
    /// Sign in with Apple gave none. Never the username or email.
    static func publicName(_ user: User) -> String {
        let name = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Friend" : name
    }

    static func friendship(_ a: String, _ b: String, on db: Database) async throws -> Friendship? {
        let (lo, hi) = a < b ? (a, b) : (b, a)
        return try await Friendship.query(on: db)
            .filter(\.$userAID == lo)
            .filter(\.$userBID == hi)
            .first()
    }

    static func areFriends(_ a: String, _ b: String, on db: Database) async throws -> Bool {
        try await friendship(a, b, on: db) != nil
    }

    static func friendIDs(of userID: String, on db: Database) async throws -> [String] {
        let rows = try await Friendship.query(on: db)
            .group(.or) { group in
                group.filter(\.$userAID == userID)
                group.filter(\.$userBID == userID)
            }
            .all()
        return rows.map { $0.userAID == userID ? $0.userBID : $0.userAID }
    }

    /// Makes two users friends. Safe to call twice; closes any pending request
    /// between them so it can't be accepted again.
    @discardableResult
    static func befriend(_ a: String, _ b: String, on db: Database) async throws -> Friendship {
        if let existing = try await friendship(a, b, on: db) {
            return existing
        }
        let friendship = Friendship(userAID: a, userBID: b)
        try await friendship.save(on: db)
        let pending = try await FriendRequest.query(on: db)
            .filter(\.$status == "pending")
            .group(.or) { or in
                or.group(.and) { $0.filter(\.$fromUserID == a); $0.filter(\.$toUserID == b) }
                or.group(.and) { $0.filter(\.$fromUserID == b); $0.filter(\.$toUserID == a) }
            }
            .all()
        for request in pending {
            request.status = "accepted"
            request.respondedAt = Date()
            try await request.save(on: db)
        }
        return friendship
    }

    // MARK: Scores

    /// Sum of one metric per user over [startDay, endDay] (inclusive).
    static func totals(
        userIDs: [String],
        from startDay: String,
        to endDay: String,
        metric: KeyPath<ArenaDailyStat, Int>,
        on db: Database
    ) async throws -> [String: Int] {
        guard !userIDs.isEmpty else { return [:] }
        let rows = try await ArenaDailyStat.query(on: db)
            .filter(\.$userID ~~ userIDs)
            .filter(\.$day >= startDay)
            .filter(\.$day <= endDay)
            .all()
        var sums: [String: Int] = [:]
        for row in rows {
            sums[row.userID, default: 0] += row[keyPath: metric]
        }
        return sums
    }

    static func weeklyXP(userIDs: [String], week: (start: String, end: String), on db: Database) async throws -> [String: Int] {
        try await totals(userIDs: userIDs, from: week.start, to: week.end, metric: \.xp, on: db)
    }

    /// Standard competition ranking: equal scores share a rank (1, 1, 3).
    /// `scores` must already be sorted high to low.
    static func ranks(for scores: [Int]) -> [Int] {
        var result: [Int] = []
        for (index, score) in scores.enumerated() {
            if index > 0, scores[index - 1] == score {
                result.append(result[index - 1])
            } else {
                result.append(index + 1)
            }
        }
        return result
    }
}
