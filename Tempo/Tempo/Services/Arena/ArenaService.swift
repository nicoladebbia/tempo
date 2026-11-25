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
    private(set) var leaderboard: ArenaLeaderboardDTO?
    /// A refresh failed but older data is on screen.
    private(set) var isStale = false

    /// What the server last said. The lists below leave out an item whose removal is
    /// waiting out its Undo window, so a refresh never brings it back early.
    private(set) var fetchedFriends: [ArenaFriendDTO] = []
    private(set) var fetchedRequests: [ArenaFriendRequestDTO] = []
    private(set) var fetchedChallenges: [ArenaChallengeDTO] = []

    /// Set when a removal that already left the screen failed on the server. The
    /// item is back on screen; this says why.
    private(set) var removalFailure: String?
    private var pendingRemoval = PendingRemoval<ArenaRemoval>()
    /// Removals whose Undo window is over and whose server call is still running.
    private var committing: Set<ArenaRemoval> = []

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    var friends: [ArenaFriendDTO] {
        fetchedFriends.filter { !isHidden(.init(kind: .friend, id: $0.id)) }
    }

    var requests: [ArenaFriendRequestDTO] {
        fetchedRequests.filter { !isHidden(.init(kind: .request, id: $0.id)) }
    }

    var challenges: [ArenaChallengeDTO] {
        fetchedChallenges.filter { !isHidden(.init(kind: .challenge, id: $0.id)) }
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
            apply(friends: friends, requests: requests, leaderboard: board, challenges: challenges)
        } catch {
            if phase == .loading || isFailed {
                phase = .failed(Self.message(for: error))
            } else {
                isStale = true
            }
        }
    }

    /// Takes what the server sent as the current state.
    func apply(
        friends: [ArenaFriendDTO], requests: [ArenaFriendRequestDTO],
        leaderboard: ArenaLeaderboardDTO?, challenges: [ArenaChallengeDTO]
    ) {
        fetchedFriends = friends
        fetchedRequests = requests
        self.leaderboard = leaderboard
        fetchedChallenges = challenges
        isStale = false
        phase = .ready
    }

    private var isFailed: Bool {
        if case .failed = phase {
            return true
        }
        return false
    }

    // MARK: - Share totals

    /// The last totals the server accepted, and for whom, so an identical push is
    /// skipped. Another account on the same phone starts from nothing.
    private static var lastPushed: (userID: String, body: ArenaStatsRequestDTO)?
    /// The push in progress. Pushes run one after another, in the order they were
    /// asked for, so an older body can never land after a newer one.
    private static var inFlight: Task<Void, Never>?

    /// Sends the user's own totals so friends' boards and challenges show real
    /// numbers. Static because it also runs from the app root, where no Arena
    /// screen (and so no instance) exists. Skips a push that would repeat the last one.
    static func push(
        _ summary: ArenaXPLedger.Summary, userID: String, displayName: String?, streakDays: Int,
        apiClient: APIClient, force: Bool = false
    ) async {
        // Records that could not be read are not the user's real numbers.
        guard !summary.isPartial else {
            return
        }
        let body = ArenaStatsRequestDTO(
            displayName: displayName, level: summary.level, xpTotal: summary.totalXP,
            streakDays: streakDays, days: summary.days
        )
        let previous = inFlight
        let task = Task {
            await previous?.value
            guard force || lastPushed?.userID != userID || lastPushed?.body != body else {
                return
            }
            do {
                _ = try await apiClient.request(APIEndpoint<ArenaStatsResponseDTO>.putArenaStats(), body: body)
                lastPushed = (userID, body)
            } catch {
                // Not shown: the next sync sends it again.
            }
        }
        inFlight = task
        await task.value
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
        fetchedRequests.removeAll { $0.id == request.id }
    }

    func remove(_ friend: ArenaFriendDTO) async throws {
        _ = try await call {
            try await self.apiClient.request(APIEndpoint<EmptyResponse>.removeFriend(friendshipId: friend.friendshipId))
        }
        fetchedFriends.removeAll { $0.id == friend.id }
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
        fetchedChallenges.removeAll { $0.id == challenge.id }
        await refresh()
    }

    // MARK: - Removal with Undo

    // Removing a friend, declining a request and leaving a challenge cannot be taken
    // back on the server, so they wait: the item leaves the screen at once, the page
    // offers Undo, and only when that window ends does the call go out. One removal
    // waits at a time; starting another makes the first final. If the app is closed
    // inside the window nothing was sent, so the item is simply still there.

    private func isHidden(_ removal: ArenaRemoval) -> Bool {
        pendingRemoval.hides(removal) || committing.contains(removal)
    }

    /// Hides the item and starts its Undo window.
    func beginRemoval(_ removal: ArenaRemoval) {
        guard !committing.contains(removal) else {
            return
        }
        removalFailure = nil
        if let replaced = pendingRemoval.begin(removal) {
            startCommit(replaced)
        }
    }

    /// Puts the item back. Nothing was sent to the server.
    func undoRemoval() {
        pendingRemoval.undo()
    }

    /// The Undo window ended: the removal goes to the server.
    func finishRemoval() {
        if let removal = pendingRemoval.finish() {
            startCommit(removal)
        }
    }

    func clearRemovalFailure() {
        removalFailure = nil
    }

    private func startCommit(_ removal: ArenaRemoval) {
        // Still hidden while the call runs, so the item does not flash back.
        committing.insert(removal)
        Task { await commit(removal) }
    }

    private func commit(_ removal: ArenaRemoval) async {
        defer { committing.remove(removal) }
        do {
            switch removal.kind {
            case .friend:
                if let friend = fetchedFriends.first(where: { $0.id == removal.id }) {
                    try await remove(friend)
                }
            case .request:
                if let request = fetchedRequests.first(where: { $0.id == removal.id }) {
                    try await decline(request)
                }
            case .challenge:
                if let challenge = fetchedChallenges.first(where: { $0.id == removal.id }) {
                    try await leave(challenge)
                }
            }
        } catch {
            removalFailure = error.localizedDescription
        }
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

// MARK: - ArenaRemoval

/// One thing the user removed that can still be taken back: a friend, a friend
/// request or a challenge, by the id the server gave it.
struct ArenaRemoval: Hashable {
    enum Kind: Hashable {
        case friend
        case request
        case challenge
    }

    let kind: Kind
    let id: String
}

// MARK: - ArenaServiceError

struct ArenaServiceError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
