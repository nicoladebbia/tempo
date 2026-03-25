import Vapor
import Fluent
import SQLKit

// MARK: - Leaderboard Controller
// Per BACKEND_API.md Section 10.5 — Weekly/monthly/alltime leaderboards.
// Uses materialized view for weekly rankings.

struct LeaderboardController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get(":period", use: leaderboard)
        routes.get("friends", use: friendsLeaderboard)
    }

    // MARK: - GET /v1/leaderboards/:period
    // Per BACKEND_API.md Section 10.5 — Period leaderboard (weekly, monthly, alltime).

    @Sendable
    func leaderboard(req: Request) async throws -> Envelope<LeaderboardDTO> {
        let userID = try req.auth.requireUserID()
        guard let period = req.parameters.get("period"),
              ["weekly", "monthly", "alltime"].contains(period) else {
            throw Abort(.badRequest, reason: "Period must be weekly, monthly, or alltime.")
        }

        let pagination = try req.query.decode(PaginationQuery.self)
        let limit = min(pagination.limit ?? 25, 100)

        guard let sql = req.db as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "SQL database required.")
        }

        let rankings: [LeaderboardRankingDTO]
        let myRank: Int
        let myXP: Int

        if period == "weekly" {
            // Use materialized view
            let rows = try await sql.raw("""
                SELECT user_id, username, display_name, level, weekly_raw_xp AS xp, rank
                FROM weekly_leaderboard
                ORDER BY rank ASC
                LIMIT \(unsafeRaw: "\(limit)")
                """).all()

            rankings = try rows.map { row in
                LeaderboardRankingDTO(
                    rank: try row.decode(column: "rank", as: Int.self),
                    user: LeaderboardUserDTO(
                        id: try row.decode(column: "user_id", as: String.self),
                        username: try row.decode(column: "username", as: String.self),
                        displayName: try row.decode(column: "display_name", as: String.self),
                        level: try row.decode(column: "level", as: Int.self)
                    ),
                    xp: try row.decode(column: "xp", as: Int.self),
                    isMe: (try row.decode(column: "user_id", as: String.self)) == userID
                )
            }

            // Get user's own rank
            let myRow = try await sql.raw("""
                SELECT rank, weekly_raw_xp AS xp FROM weekly_leaderboard
                WHERE user_id = \(bind: userID)
                """).first()
            myRank = (try? myRow?.decode(column: "rank", as: Int.self)) ?? 0
            myXP = (try? myRow?.decode(column: "xp", as: Int.self)) ?? 0

        } else {
            // For monthly/alltime, aggregate from xp_events
            let dateFilter: String
            if period == "monthly" {
                dateFilter = "AND xe.created_at >= date_trunc('month', CURRENT_DATE)"
            } else {
                dateFilter = "" // alltime
            }

            let rows = try await sql.raw("""
                SELECT
                    u.id AS user_id,
                    u.username,
                    u.display_name,
                    u.level,
                    COALESCE(SUM(xe.base_xp), 0) AS xp,
                    RANK() OVER (ORDER BY COALESCE(SUM(xe.base_xp), 0) DESC) AS rank
                FROM users u
                LEFT JOIN xp_events xe ON xe.user_id = u.id \(unsafeRaw: dateFilter)
                WHERE u.deleted_at IS NULL
                GROUP BY u.id, u.username, u.display_name, u.level
                ORDER BY xp DESC
                LIMIT \(unsafeRaw: "\(limit)")
                """).all()

            rankings = try rows.map { row in
                LeaderboardRankingDTO(
                    rank: try row.decode(column: "rank", as: Int.self),
                    user: LeaderboardUserDTO(
                        id: try row.decode(column: "user_id", as: String.self),
                        username: try row.decode(column: "username", as: String.self),
                        displayName: try row.decode(column: "display_name", as: String.self),
                        level: try row.decode(column: "level", as: Int.self)
                    ),
                    xp: try row.decode(column: "xp", as: Int.self),
                    isMe: (try row.decode(column: "user_id", as: String.self)) == userID
                )
            }

            let myRow = try await sql.raw("""
                SELECT
                    RANK() OVER (ORDER BY COALESCE(SUM(xe.base_xp), 0) DESC) AS rank,
                    COALESCE(SUM(xe.base_xp), 0) AS xp
                FROM users u
                LEFT JOIN xp_events xe ON xe.user_id = u.id \(unsafeRaw: dateFilter)
                WHERE u.deleted_at IS NULL
                GROUP BY u.id
                HAVING u.id = \(bind: userID)
                """).first()
            myRank = (try? myRow?.decode(column: "rank", as: Int.self)) ?? 0
            myXP = (try? myRow?.decode(column: "xp", as: Int.self)) ?? 0
        }

        let calendar = Calendar(identifier: .iso8601)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

        return Envelope(
            data: LeaderboardDTO(
                period: period,
                weekStart: weekStart,
                myRank: myRank,
                myXP: myXP,
                rankings: rankings
            ),
            requestID: req.requestID
        )
    }

    // MARK: - GET /v1/leaderboards/friends
    // Friends-only leaderboard filtered to user's friends.

    @Sendable
    func friendsLeaderboard(req: Request) async throws -> Envelope<LeaderboardDTO> {
        let userID = try req.auth.requireUserID()

        // Get friend IDs
        let friendships = try await Friendship.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$userAID == userID)
                group.filter(\.$userBID == userID)
            }
            .all()

        var friendIDs = friendships.map { f in
            f.userAID == userID ? f.userBID : f.userAID
        }
        friendIDs.append(userID) // Include self

        guard let sql = req.db as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "SQL database required.")
        }

        // Use weekly period for friends leaderboard
        let rows = try await sql.raw("""
            SELECT user_id, username, display_name, level, weekly_raw_xp AS xp, rank
            FROM weekly_leaderboard
            WHERE user_id IN (\(unsafeRaw: friendIDs.map { "'\($0)'" }.joined(separator: ", ")))
            ORDER BY xp DESC
            """).all()

        var rankings: [LeaderboardRankingDTO] = []
        for (i, row) in rows.enumerated() {
            rankings.append(LeaderboardRankingDTO(
                rank: i + 1, // Re-rank among friends
                user: LeaderboardUserDTO(
                    id: try row.decode(column: "user_id", as: String.self),
                    username: try row.decode(column: "username", as: String.self),
                    displayName: try row.decode(column: "display_name", as: String.self),
                    level: try row.decode(column: "level", as: Int.self)
                ),
                xp: try row.decode(column: "xp", as: Int.self),
                isMe: (try row.decode(column: "user_id", as: String.self)) == userID
            ))
        }

        let myRank = rankings.first(where: { $0.isMe })?.rank ?? 0
        let myXP = rankings.first(where: { $0.isMe })?.xp ?? 0

        return Envelope(
            data: LeaderboardDTO(
                period: "weekly",
                weekStart: Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: Date())?.start ?? Date(),
                myRank: myRank,
                myXP: myXP,
                rankings: rankings
            ),
            requestID: req.requestID
        )
    }
}

// MARK: - DTOs

struct LeaderboardDTO: Content {
    let period: String
    let weekStart: Date
    let myRank: Int
    let myXP: Int
    let rankings: [LeaderboardRankingDTO]

    enum CodingKeys: String, CodingKey {
        case period
        case weekStart = "week_start"
        case myRank = "my_rank"
        case myXP = "my_xp"
        case rankings
    }
}

struct LeaderboardRankingDTO: Content {
    let rank: Int
    let user: LeaderboardUserDTO
    let xp: Int
    let isMe: Bool

    enum CodingKeys: String, CodingKey {
        case rank, user, xp
        case isMe = "is_me"
    }
}

struct LeaderboardUserDTO: Content {
    let id: String
    let username: String
    let displayName: String
    let level: Int

    enum CodingKeys: String, CodingKey {
        case id, username, level
        case displayName = "display_name"
    }
}
