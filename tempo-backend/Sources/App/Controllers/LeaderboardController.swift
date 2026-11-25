import Fluent
import Vapor

// MARK: - Leaderboard Controller

//
// Per BACKEND_API.md Section 10.5 — leaderboards, narrowed to friends.
//
// There is deliberately no global board (it used to list every user to any
// signed-in user): the only leaderboard is you and your friends, ranked by the
// XP each of you earned this ISO week. The numbers are live sums over
// arena_daily_stats (what each app pushed), bound to the server clock, so a new
// friend with no XP yet still shows with 0 and the test clock moves the week.

struct LeaderboardController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("friends", use: friendsLeaderboard)
    }

    // MARK: - GET /v1/leaderboards/friends

    // Optional ?week_start=YYYY-MM-DD: the app's own current week.

    @Sendable
    func friendsLeaderboard(req: Request) async throws -> Envelope<LeaderboardDTO> {
        let userID = try req.auth.requireUserID()
        let week = ArenaService.week(containing: req.now, requestedStart: try? req.query.get(String.self, at: "week_start"))

        let friendIDs = try await ArenaService.friendIDs(of: userID, on: req.db)
        let everyone = [userID] + friendIDs
        let users = try await User.query(on: req.db)
            .filter(\.$id ~~ everyone)
            .filter(\.$deletedAt == nil)
            .all()
        let weekly = try await ArenaService.weeklyXP(userIDs: everyone, week: week, on: req.db)

        // High to low; equal XP shares a rank and is ordered by name so the
        // list does not shuffle between refreshes.
        let ordered = users
            .map { (user: $0, xp: weekly[$0.id ?? ""] ?? 0) }
            .sorted {
                $0.xp != $1.xp
                    ? $0.xp > $1.xp
                    : ArenaService.publicName($0.user).localizedCaseInsensitiveCompare(ArenaService.publicName($1.user)) == .orderedAscending
            }
        let ranks = ArenaService.ranks(for: ordered.map(\.xp))

        var rankings: [LeaderboardRankingDTO] = []
        for (index, entry) in ordered.enumerated() {
            let id = try entry.user.requireID()
            rankings.append(LeaderboardRankingDTO(
                rank: ranks[index],
                user: LeaderboardUserDTO(
                    id: id,
                    displayName: ArenaService.publicName(entry.user),
                    level: entry.user.level
                ),
                xp: entry.xp,
                isMe: id == userID
            ))
        }

        let me = rankings.first(where: \.isMe)
        return Envelope(
            data: LeaderboardDTO(
                period: "weekly",
                weekStart: ArenaService.parseDay(week.start) ?? req.now,
                myRank: me?.rank ?? 0,
                myXP: me?.xp ?? 0,
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

/// What a friend shows on the board: a name and a level.
struct LeaderboardUserDTO: Content {
    let id: String
    let displayName: String
    let level: Int

    enum CodingKeys: String, CodingKey {
        case id, level
        case displayName = "display_name"
    }
}
