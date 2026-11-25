import Fluent
import Vapor

// MARK: - Arena Stats Controller

//
// PUT /v1/arena/stats — the app tells the server what it measured.
//
// XP is earned and added up on the phone (its local XP rows are the source of
// truth for the level, the streak and every XP figure the user sees). To let
// friends compare, the app pushes its per-day totals here and the server only
// sums them. Pushing a day again replaces it, so the call is idempotent and a
// retry or a backfill never double-counts.
//
// Trust model: friends-only, so the values are taken at face value but bounded
// (a day can't hold more than a person could earn, and only recent days count).

struct ArenaStatsController: RouteCollection {
    static let maxDaysBack = 62
    static let maxXPPerDay = 5000
    static let maxWorkoutsPerDay = 20
    static let maxStudyMinutesPerDay = 1440

    func boot(routes: RoutesBuilder) throws {
        routes.put("stats", use: putStats)
    }

    @Sendable
    func putStats(req: Request) async throws -> Envelope<ArenaStatsSavedDTO> {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(ArenaStatsRequestDTO.self)
        guard body.days.count <= Self.maxDaysBack + 3 else {
            throw Abort(.badRequest, reason: "Too many days in one push.")
        }
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        let today = ArenaService.dayString(req.now)
        let oldest = ArenaService.addDays(-Self.maxDaysBack, to: today) ?? today
        // One day ahead: a phone east of the server is already on tomorrow.
        let newest = ArenaService.addDays(1, to: today) ?? today

        // Last write wins per day when a day is repeated in one push.
        var byDay: [String: ArenaStatsDayDTO] = [:]
        for day in body.days {
            guard ArenaService.parseDay(day.day) != nil else {
                throw Abort(.badRequest, reason: "Day must look like 2026-11-23.")
            }
            guard day.day >= oldest, day.day <= newest else { continue }
            byDay[day.day] = day
        }

        let existing = try await ArenaDailyStat.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$day ~~ Array(byDay.keys))
            .all()
        var rows = Dictionary(uniqueKeysWithValues: existing.map { ($0.day, $0) })

        for (day, value) in byDay {
            let xp = min(max(value.xp, 0), Self.maxXPPerDay)
            let workouts = min(max(value.workouts, 0), Self.maxWorkoutsPerDay)
            let study = min(max(value.studyMinutes, 0), Self.maxStudyMinutesPerDay)
            if let row = rows[day] {
                row.xp = xp
                row.workouts = workouts
                row.studyMinutes = study
                try await row.save(on: req.db)
            } else if xp > 0 || workouts > 0 || study > 0 {
                // A day with nothing in it and no row on file needs no row: the phone sends
                // the whole window so that a day that lost its XP is corrected here too.
                let row = ArenaDailyStat(userID: userID, day: day, xp: xp, workouts: workouts, studyMinutes: study)
                do {
                    try await row.save(on: req.db)
                    rows[day] = row
                } catch {
                    // A second push from the same phone inserted this day first (unique user + day):
                    // its row is the one to update.
                    guard let winner = try await ArenaDailyStat.query(on: req.db)
                        .filter(\.$userID == userID)
                        .filter(\.$day == day)
                        .first()
                    else {
                        throw error
                    }
                    winner.xp = xp
                    winner.workouts = workouts
                    winner.studyMinutes = study
                    try await winner.save(on: req.db)
                    rows[day] = winner
                }
            }
        }

        // What friends see next to the name. The level is the one the user's own
        // app shows (it owns the level table); the server only bounds it.
        user.level = min(max(body.level, 1), 100)
        user.xpTotal = min(max(body.xpTotal, 0), 10_000_000)
        user.streakDays = min(max(body.streakDays, 0), 100_000)
        if let name = body.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            user.displayName = String(name.prefix(40))
        }
        try await user.save(on: req.db)

        return Envelope(data: ArenaStatsSavedDTO(daysSaved: byDay.count), requestID: req.requestID)
    }
}

// MARK: - DTOs

/// Request bodies: decoded by the global `.convertFromSnakeCase` decoder, so plain
/// camelCase properties and no CodingKeys.
struct ArenaStatsDayDTO: Content {
    /// "YYYY-MM-DD" in the user's own calendar.
    let day: String
    let xp: Int
    let workouts: Int
    let studyMinutes: Int
}

struct ArenaStatsRequestDTO: Content {
    let displayName: String?
    let level: Int
    let xpTotal: Int
    let streakDays: Int
    let days: [ArenaStatsDayDTO]
}

struct ArenaStatsSavedDTO: Content {
    let daysSaved: Int

    enum CodingKeys: String, CodingKey {
        case daysSaved = "days_saved"
    }
}
