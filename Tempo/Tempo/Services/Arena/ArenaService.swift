//
// ArenaService.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import Foundation

// MARK: - ArenaService

// Everything the Arena asks the server: who your friends are, who is waiting on
// an answer, where you rank this week, your challenges, your invite link, and
// the totals you share with friends. Self-contained, like SharedGroceryListService:
// ArenaTabView owns one and hands it to the Arena pages through the environment.
//
// Friends see only a display name, a level and one week of XP. Nothing else
// leaves the phone (see ArenaStatsRequestDTO).

@MainActor
@Observable
final class ArenaService {
    enum Phase: Equatable {
        /// Nothing asked yet.
        case idle
        /// The first load is under way.
        case loading
        case ready
        /// The first load failed and there is nothing to show.
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var friends: [ArenaFriendDTO] = []
    private(set) var requests: [ArenaFriendRequestDTO] = []
    private(set) var leaderboard: ArenaLeaderboardDTO?
    private(set) var challenges: [ArenaChallengeDTO] = []
    /// A refresh failed but older data is on screen.
    private(set) var isStale = false

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    var incomingRequests: [ArenaFriendRequestDTO] {
        requests.filter(\.isIncoming)
    }

    var outgoingRequests: [ArenaFriendRequestDTO] {
        requests.filter { !$0.isIncoming }
    }

    /// Challenges someone invited you to and you have not answered.
    var invitedChallenges: [ArenaChallengeDTO] {
        challenges.filter { $0.myStatus == "invited" && $0.status != "completed" }
    }

    /// Challenges you are in that have not finished.
    var runningChallenges: [ArenaChallengeDTO] {
        challenges.filter { $0.myStatus == "joined" && $0.status != "completed" }
    }

    var finishedChallenges: [ArenaChallengeDTO] {
        challenges.filter { $0.myStatus == "joined" && $0.status == "completed" }
    }

    // MARK: - Load

    /// Asks for everything at once. Keeps what is on screen when a refresh fails.
    func refresh(now: Date = Date()) async {
        if phase == .idle || isFailed {
            phase = .loading
        }
        let weekStart = ArenaCalendar.dayKey(ArenaCalendar.weekStart(containing: now))
        do {
            async let friendsRequest = apiClient.request(APIEndpoint<[ArenaFriendDTO]>.listFriends())
            async let requestsRequest = apiClient.request(APIEndpoint<[ArenaFriendRequestDTO]>.listFriendRequests())
            async let boardRequest = apiClient.request(
                APIEndpoint<ArenaLeaderboardDTO>.friendsLeaderboard(),
                queryItems: [URLQueryItem(name: "week_start", value: weekStart)]
            )
            async let challengesRequest = apiClient.request(APIEndpoint<[ArenaChallengeDTO]>.listChallenges())
            let (friends, requests, board, challenges) = try await (
                friendsRequest, requestsRequest, boardRequest, challengesRequest
            )
            self.friends = friends
            self.requests = requests
            leaderboard = board
            self.challenges = challenges
            isStale = false
            phase = .ready
        } catch {
            if phase == .loading || isFailed {
                phase = .failed(Self.message(for: error))
            } else {
                isStale = true
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = phase {
            return true
        }
        return false
    }

    // MARK: - Share totals

    /// The last totals the server accepted, so an identical push is skipped.
    private static var lastPushed: ArenaStatsRequestDTO?

    /// Sends the user's own totals so friends' boards and challenges show real
    /// numbers. Static because it also runs from the app root, where no Arena
    /// screen (and so no instance) exists. Skips a push that would repeat the last one.
    static func push(
        _ summary: ArenaXPLedger.Summary, displayName: String?, streakDays: Int,
        apiClient: APIClient, force: Bool = false
    ) async {
        let body = ArenaStatsRequestDTO(
            displayName: displayName, level: summary.level, xpTotal: summary.totalXP,
            streakDays: streakDays, days: summary.days
        )
        guard force || body != lastPushed else {
            return
        }
        do {
            _ = try await apiClient.request(APIEndpoint<ArenaStatsResponseDTO>.putArenaStats(), body: body)
            lastPushed = body
        } catch {
            // Not shown: the next sync sends it again.
        }
    }

    // MARK: - Invite link

    /// The user's live invite link; made on first use.
    func inviteLink() async throws -> ArenaInviteDTO {
        try await call { try await self.apiClient.request(APIEndpoint<ArenaInviteDTO>.createFriendInvite()) }
    }

    /// Kills the current link; the next `inviteLink()` makes a new one.
    func revokeInviteLink() async throws {
        _ = try await call { try await self.apiClient.request(APIEndpoint<EmptyResponse>.revokeFriendInvite()) }
    }

    // MARK: - Friends

    func accept(_ request: ArenaFriendRequestDTO) async throws {
        _ = try await call {
            try await self.apiClient.request(APIEndpoint<ArenaFriendDTO>.acceptFriendRequest(id: request.id))
        }
        await refresh()
    }

    func decline(_ request: ArenaFriendRequestDTO) async throws {
        _ = try await call {
            try await self.apiClient.request(APIEndpoint<EmptyResponse>.declineFriendRequest(id: request.id))
        }
        requests.removeAll { $0.id == request.id }
    }

    func remove(_ friend: ArenaFriendDTO) async throws {
        _ = try await call {
            try await self.apiClient.request(APIEndpoint<EmptyResponse>.removeFriend(friendshipId: friend.friendshipId))
        }
        await refresh()
    }

    // MARK: - Challenges

    @discardableResult
    func createChallenge(_ body: ArenaChallengeCreateDTO) async throws -> ArenaChallengeDTO {
        let created = try await call {
            try await self.apiClient.request(APIEndpoint<ArenaChallengeDTO>.createChallenge(), body: body)
        }
        await refresh()
        return created
    }

    func join(_ challenge: ArenaChallengeDTO) async throws {
        _ = try await call { try await self.apiClient.request(APIEndpoint<EmptyResponse>.joinChallenge(id: challenge.id)) }
        await refresh()
    }

    /// Leaves a challenge, or declines an invitation to one.
    func leave(_ challenge: ArenaChallengeDTO) async throws {
        _ = try await call { try await self.apiClient.request(APIEndpoint<EmptyResponse>.leaveChallenge(id: challenge.id)) }
        await refresh()
    }

    // MARK: - Errors

    /// Runs a call and turns any failure into an `ArenaServiceError` with a sentence worth showing.
    private func call<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            throw ArenaServiceError(message: Self.message(for: error))
        }
    }

    /// Plain words for what went wrong.
    nonisolated static func message(for error: Error) -> String {
        guard let api = error as? APIError else {
            return "Something went wrong. Try again."
        }
        switch api {
        case .networkError,
             .connectionRefused,
             .timeout,
             .noResponse:
            return "No connection. Check your internet and try again."
        case .rateLimited:
            return "Too many tries. Wait a minute and try again."
        case .unauthorized:
            return "You were signed out. Sign in again."
        case .notFound:
            return "That link or person is no longer available."
        case .forbidden:
            return "You can only do that with friends."
        case .conflict:
            return "That is already done."
        default:
            return "Something went wrong. Try again."
        }
    }
}

// MARK: - ArenaServiceError

struct ArenaServiceError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
