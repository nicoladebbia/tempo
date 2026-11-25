//
// APIEndpoints+Arena.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import Foundation

// MARK: - ArenaStatsDayDTO

//
// Mirror the backend's FriendController, LeaderboardController,
// ChallengeController and ArenaStatsController. The server encodes snake_case
// and decodes with `.convertFromSnakeCase`; this app's APIClient coders have
// NO key strategy, so every multi-word property carries an explicit CodingKey,
// in both directions. `contracts/golden/*.json` pins every shape (see
// APIContractTests).
//
// A few shapes worth knowing:
//   - user ids are opaque strings (`usr_...`), never parsed as UUIDs
//   - challenge `start_day` / `end_day` are date-only strings ("2026-11-24"),
//     which the ISO8601 decoder would reject, so they stay `String`
//   - `rank` / `my_rank` are absent for someone who is only invited

/// One day of what the user did, pushed so friends' boards and challenges
/// can rank real activity. Never sent to anyone but friends, and only as totals.
struct ArenaStatsDayDTO: Codable, Sendable, Equatable {
    /// "YYYY-MM-DD" in the user's calendar.
    let day: String
    let xp: Int
    let workouts: Int
    let studyMinutes: Int

    enum CodingKeys: String, CodingKey {
        case day
        case xp
        case workouts
        case studyMinutes = "study_minutes"
    }
}

// MARK: - ArenaStatsRequestDTO

struct ArenaStatsRequestDTO: Codable, Sendable, Equatable {
    var displayName: String?
    let level: Int
    let xpTotal: Int
    let streakDays: Int
    let days: [ArenaStatsDayDTO]

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case level
        case xpTotal = "xp_total"
        case streakDays = "streak_days"
        case days
    }
}

// MARK: - ArenaStatsResponseDTO

struct ArenaStatsResponseDTO: Codable, Sendable {
    let daysSaved: Int

    enum CodingKeys: String, CodingKey {
        case daysSaved = "days_saved"
    }
}

// MARK: - ArenaFriendDTO

struct ArenaFriendDTO: Codable, Sendable, Equatable, Identifiable {
    let friendshipId: String
    let userId: String
    let displayName: String
    let level: Int
    /// Only this ISO week's XP is ever shared.
    let weeklyXP: Int
    let friendsSince: Date

    var id: String {
        friendshipId
    }

    enum CodingKeys: String, CodingKey {
        case friendshipId = "friendship_id"
        case userId = "user_id"
        case displayName = "display_name"
        case level
        case weeklyXP = "weekly_xp"
        case friendsSince = "friends_since"
    }
}

// MARK: - ArenaFriendRequestDTO

struct ArenaFriendRequestDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    /// "pending" while it waits for an answer.
    let status: String
    /// "incoming" (someone asked you) or "outgoing" (you asked them).
    let direction: String
    let displayName: String
    let level: Int
    let createdAt: Date

    var isIncoming: Bool {
        direction == "incoming"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case direction
        case displayName = "display_name"
        case level
        case createdAt = "created_at"
    }
}

// MARK: - ArenaSendRequestBodyDTO

struct ArenaSendRequestBodyDTO: Codable, Sendable, Equatable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: - ArenaInviteDTO

struct ArenaInviteDTO: Codable, Sendable, Equatable {
    let token: String
    /// The public https page that opens the app (or says what Tempo is).
    let url: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case token
        case url
        case displayName = "display_name"
    }
}

// MARK: - ArenaInvitePreviewDTO

/// What the person who opens a link sees before saying yes: a name and a level.
struct ArenaInvitePreviewDTO: Codable, Sendable, Equatable {
    let displayName: String
    let level: Int
    /// The link is yours.
    let isOwn: Bool
    let alreadyFriends: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case level
        case isOwn = "is_own"
        case alreadyFriends = "already_friends"
    }
}

// MARK: - ArenaLeaderboardUserDTO

struct ArenaLeaderboardUserDTO: Codable, Sendable, Equatable {
    let id: String
    let displayName: String
    let level: Int

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case level
    }
}

// MARK: - ArenaLeaderboardRankingDTO

struct ArenaLeaderboardRankingDTO: Codable, Sendable, Equatable, Identifiable {
    let rank: Int
    let user: ArenaLeaderboardUserDTO
    let xp: Int
    let isMe: Bool

    var id: String {
        user.id
    }

    enum CodingKeys: String, CodingKey {
        case rank
        case user
        case xp
        case isMe = "is_me"
    }
}

// MARK: - ArenaLeaderboardDTO

struct ArenaLeaderboardDTO: Codable, Sendable, Equatable {
    /// Always "weekly": the board covers one ISO week, Monday to Sunday.
    let period: String
    let weekStart: Date
    /// nil when there is nobody to rank against.
    let myRank: Int?
    let myXP: Int
    let rankings: [ArenaLeaderboardRankingDTO]

    enum CodingKeys: String, CodingKey {
        case period
        case weekStart = "week_start"
        case myRank = "my_rank"
        case myXP = "my_xp"
        case rankings
    }
}

// MARK: - ArenaChallengeParticipantDTO

struct ArenaChallengeParticipantDTO: Codable, Sendable, Equatable, Identifiable {
    let displayName: String
    let level: Int
    let score: Int
    /// Absent while the person is only invited.
    let rank: Int?
    let isMe: Bool
    /// "joined" or "invited".
    let status: String

    var id: String {
        "\(displayName)-\(status)-\(isMe)"
    }

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case level
        case score
        case rank
        case isMe = "is_me"
        case status
    }
}

// MARK: - ArenaChallengeDTO

struct ArenaChallengeDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let isCreator: Bool
    let title: String
    let description: String
    let type: String
    /// "xp_total", "workout_count" or "study_minutes".
    let metric: String
    /// "YYYY-MM-DD", first day inclusive.
    let startDay: String
    /// "YYYY-MM-DD", last day inclusive.
    let endDay: String
    let maxParticipants: Int
    let visibility: String
    /// "upcoming", "active" or "completed".
    let status: String
    /// "joined" or "invited".
    let myStatus: String
    let myScore: Int
    let myRank: Int?
    let memberCount: Int
    let participants: [ArenaChallengeParticipantDTO]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case isCreator = "is_creator"
        case title
        case description
        case type
        case metric
        case startDay = "start_day"
        case endDay = "end_day"
        case maxParticipants = "max_participants"
        case visibility
        case status
        case myStatus = "my_status"
        case myScore = "my_score"
        case myRank = "my_rank"
        case memberCount = "member_count"
        case participants
        case createdAt = "created_at"
    }
}

// MARK: - ArenaChallengeCreateDTO

struct ArenaChallengeCreateDTO: Codable, Sendable, Equatable {
    let title: String
    let description: String?
    let metric: String
    let durationDays: Int
    /// "YYYY-MM-DD"; the server defaults to today.
    let startsOn: String?
    let maxParticipants: Int?
    /// Friends' `user_id`s; the server refuses anyone who is not a friend.
    let inviteUserIds: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case metric
        case durationDays = "duration_days"
        case startsOn = "starts_on"
        case maxParticipants = "max_participants"
        case inviteUserIds = "invite_user_ids"
    }
}

// MARK: - Endpoints

extension APIEndpoint where Response == ArenaStatsResponseDTO {
    /// `PUT /v1/arena/stats` — replace the last days of the user's totals.
    static func putArenaStats() -> Self {
        APIEndpoint(path: "/v1/arena/stats", method: .put, changesReads: true)
    }
}

extension APIEndpoint where Response == [ArenaFriendDTO] {
    /// `GET /v1/friends`
    static func listFriends() -> Self {
        APIEndpoint(path: "/v1/friends", method: .get)
    }
}

extension APIEndpoint where Response == [ArenaFriendRequestDTO] {
    /// `GET /v1/friends/requests` — both directions, pending only.
    static func listFriendRequests() -> Self {
        APIEndpoint(path: "/v1/friends/requests", method: .get)
    }
}

extension APIEndpoint where Response == ArenaFriendRequestDTO {
    /// `POST /v1/friends/requests`
    static func sendFriendRequest() -> Self {
        APIEndpoint(path: "/v1/friends/requests", method: .post)
    }
}

extension APIEndpoint where Response == ArenaFriendDTO {
    /// `POST /v1/friends/requests/:id/accept`
    static func acceptFriendRequest(id: String) -> Self {
        APIEndpoint(path: "/v1/friends/requests/\(id)/accept", method: .post)
    }

    /// `POST /v1/friends/invites/:token/accept` — opening someone's link and saying yes.
    static func acceptFriendInvite(token: String) -> Self {
        APIEndpoint(path: "/v1/friends/invites/\(token)/accept", method: .post)
    }
}

extension APIEndpoint where Response == ArenaInviteDTO {
    /// `POST /v1/friends/invite` — the user's one live link (made on first use).
    static func createFriendInvite() -> Self {
        APIEndpoint(path: "/v1/friends/invite", method: .post)
    }
}

extension APIEndpoint where Response == ArenaInvitePreviewDTO {
    /// `GET /v1/friends/invites/:token`
    static func previewFriendInvite(token: String) -> Self {
        APIEndpoint(path: "/v1/friends/invites/\(token)", method: .get)
    }
}

extension APIEndpoint where Response == ArenaLeaderboardDTO {
    /// `GET /v1/leaderboards/friends?week_start=YYYY-MM-DD`
    static func friendsLeaderboard() -> Self {
        APIEndpoint(path: "/v1/leaderboards/friends", method: .get)
    }
}

extension APIEndpoint where Response == [ArenaChallengeDTO] {
    /// `GET /v1/challenges` — mine: joined and invited, newest first.
    static func listChallenges() -> Self {
        APIEndpoint(path: "/v1/challenges", method: .get)
    }
}

extension APIEndpoint where Response == ArenaChallengeDTO {
    /// `POST /v1/challenges`
    static func createChallenge() -> Self {
        APIEndpoint(path: "/v1/challenges", method: .post)
    }

    /// `GET /v1/challenges/:id`
    static func challengeDetail(id: String) -> Self {
        APIEndpoint(path: "/v1/challenges/\(id)", method: .get)
    }
}

extension APIEndpoint where Response == EmptyResponse {
    /// `POST /v1/friends/requests/:id/decline`
    static func declineFriendRequest(id: String) -> Self {
        APIEndpoint(path: "/v1/friends/requests/\(id)/decline", method: .post)
    }

    /// `DELETE /v1/friends/:friendshipId`
    static func removeFriend(friendshipId: String) -> Self {
        APIEndpoint(path: "/v1/friends/\(friendshipId)", method: .delete)
    }

    /// `POST /v1/friends/invite/revoke` — the old link stops working.
    static func revokeFriendInvite() -> Self {
        APIEndpoint(path: "/v1/friends/invite/revoke", method: .post)
    }

    /// `POST /v1/challenges/:id/join`
    static func joinChallenge(id: String) -> Self {
        APIEndpoint(path: "/v1/challenges/\(id)/join", method: .post)
    }

    /// `POST /v1/challenges/:id/leave` — also how an invitation is declined.
    static func leaveChallenge(id: String) -> Self {
        APIEndpoint(path: "/v1/challenges/\(id)/leave", method: .post)
    }
}
