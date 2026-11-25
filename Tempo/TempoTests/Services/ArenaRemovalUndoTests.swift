//
// ArenaRemovalUndoTests.swift
// Tempo
//
// Removing a friend, declining a request and leaving a challenge wait for their Undo
// window: the item leaves the lists at once, nothing is sent while Undo is possible,
// and the server is asked exactly once when the window ends. A refused removal
// puts the item back and says why.
//

@testable import Tempo
import XCTest

@MainActor
final class ArenaRemovalUndoTests: XCTestCase {
    private var arena: ArenaService!

    override func setUp() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.setHandler { request in
            // Every call succeeds with an empty body, unless a test installs its own handler.
            guard request.url != nil else {
                return .init(statusCode: 500)
            }
            return .init(statusCode: 200, data: Data("{}".utf8))
        }
        let api = APIClient(baseURL: URL(string: "https://stub.test")!, session: MockURLProtocol.makeSession())
        arena = ArenaService(apiClient: api)
        arena.apply(
            friends: [friend("f1", "Ana"), friend("f2", "Ben")],
            requests: [request("r1", "Caro"), request("r2", "Dan")],
            leaderboard: nil,
            challenges: [challenge("c1"), challenge("c2")]
        )
    }

    override func tearDown() async throws {
        // A removal that went out refreshes the lists afterwards. Let that finish, or its
        // requests land in the next test's record.
        var last = -1
        for _ in 0 ..< 100 {
            let count = MockURLProtocol.recordedRequests.count
            if count == last {
                break
            }
            last = count
            try? await Task.sleep(for: .milliseconds(40))
        }
        MockURLProtocol.reset()
    }

    // MARK: Fixtures

    private func friend(_ id: String, _ name: String) -> ArenaFriendDTO {
        ArenaFriendDTO(friendshipId: id, userId: "u-\(id)", displayName: name, level: 3, weeklyXP: 120, friendsSince: .now)
    }

    private func request(_ id: String, _ name: String) -> ArenaFriendRequestDTO {
        ArenaFriendRequestDTO(
            id: id, status: "pending", direction: "incoming", displayName: name, level: 2, createdAt: .now
        )
    }

    private func challenge(_ id: String) -> ArenaChallengeDTO {
        ArenaChallengeDTO(
            id: id, isCreator: false, title: "Week \(id)", description: "", type: "group", metric: "xp_total",
            startDay: "2026-11-23", endDay: "2026-11-29", maxParticipants: 10, visibility: "private",
            status: "active", myStatus: "joined", myScore: 40, myRank: 1, memberCount: 2,
            participants: [], createdAt: .now
        )
    }

    private func friendIDs() -> [String] {
        arena.friends.map(\.id)
    }

    private func calls(_ method: String, containing path: String) -> Int {
        MockURLProtocol.recordedRequests.count {
            $0.httpMethod == method && ($0.url?.path ?? "").contains(path)
        }
    }

    /// Waits (briefly) for something the removal does in the background.
    private func wait(for condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Hide, Undo

    func testARemovedFriendLeavesTheListAtOnceAndNothingIsSent() {
        arena.beginRemoval(ArenaRemoval(kind: .friend, id: "f1"))
        XCTAssertEqual(friendIDs(), ["f2"])
        XCTAssertTrue(MockURLProtocol.recordedRequests.isEmpty)
    }

    func testUndoPutsTheFriendBackAndTheServerIsNeverAsked() async {
        arena.beginRemoval(ArenaRemoval(kind: .friend, id: "f1"))
        arena.undoRemoval()
        // The toast ends after Undo.
        arena.finishRemoval()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(friendIDs(), ["f1", "f2"])
        XCTAssertTrue(MockURLProtocol.recordedRequests.isEmpty)
    }

    func testAFreshListFromTheServerDoesNotBringBackAnItemInItsUndoWindow() {
        arena.beginRemoval(ArenaRemoval(kind: .friend, id: "f1"))
        // A refresh that started before the removal lands with the old list.
        arena.apply(
            friends: [friend("f1", "Ana"), friend("f2", "Ben")], requests: [], leaderboard: nil, challenges: []
        )
        XCTAssertEqual(friendIDs(), ["f2"])
    }

    // MARK: Commit

    func testWhenTheWindowEndsTheServerIsAskedOnceAndTheFriendStaysGone() async {
        arena.beginRemoval(ArenaRemoval(kind: .friend, id: "f1"))
        arena.finishRemoval()
        // The call is on its way: the friend must not flash back meanwhile.
        XCTAssertEqual(friendIDs(), ["f2"])

        await wait { !self.arena.fetchedFriends.contains { $0.id == "f1" } }
        XCTAssertEqual(calls("DELETE", containing: "/v1/friends/f1"), 1)
        XCTAssertEqual(friendIDs(), ["f2"])

        // The page leaving after the toast: nothing more is sent.
        arena.finishRemoval()
        XCTAssertEqual(calls("DELETE", containing: "/v1/friends/f1"), 1)
    }

    func testARefusedRemovalPutsTheFriendBackAndSaysWhy() async {
        MockURLProtocol.setHandler { request in
            request.httpMethod == "DELETE" ? .init(statusCode: 403, data: Data("{}".utf8)) : .init(statusCode: 200, data: Data("{}".utf8))
        }
        arena.beginRemoval(ArenaRemoval(kind: .friend, id: "f1"))
        arena.finishRemoval()

        await wait { self.arena.removalFailure != nil }
        XCTAssertNotNil(arena.removalFailure)
        XCTAssertEqual(friendIDs(), ["f1", "f2"])
    }

    func testRemovingASecondItemMakesTheFirstFinalAndKeepsTheSecondUndoable() async {
        arena.beginRemoval(ArenaRemoval(kind: .friend, id: "f1"))
        arena.beginRemoval(ArenaRemoval(kind: .friend, id: "f2"))

        await wait { self.calls("DELETE", containing: "/v1/friends/f1") == 1 }
        XCTAssertEqual(calls("DELETE", containing: "/v1/friends/f1"), 1)
        XCTAssertEqual(calls("DELETE", containing: "/v1/friends/f2"), 0)
        XCTAssertTrue(friendIDs().isEmpty)

        arena.undoRemoval()
        XCTAssertEqual(friendIDs(), ["f2"])
    }

    // MARK: Leaderboard

    private func board() -> ArenaLeaderboardDTO {
        func row(_ rank: Int, _ id: String, _ xp: Int, me: Bool = false) -> ArenaLeaderboardRankingDTO {
            ArenaLeaderboardRankingDTO(
                rank: rank, user: ArenaLeaderboardUserDTO(id: id, displayName: id, level: 3), xp: xp, isMe: me
            )
        }
        return ArenaLeaderboardDTO(
            period: "weekly", weekStart: .now, myRank: 2, myXP: 100,
            rankings: [row(1, "u-f1", 200), row(2, "me", 100, me: true), row(3, "u-f2", 50)]
        )
    }

    func testAFriendBeingRemovedLeavesTheBoardAndTheRanksCloseUp() {
        let original = board()
        arena.apply(
            friends: [friend("f1", "Ana"), friend("f2", "Ben")], requests: [], leaderboard: original, challenges: []
        )
        XCTAssertEqual(arena.leaderboard?.rankings.count, 3)

        arena.beginRemoval(ArenaRemoval(kind: .friend, id: "f1"))
        XCTAssertEqual(arena.leaderboard?.rankings.map(\.user.id), ["me", "u-f2"])
        XCTAssertEqual(arena.leaderboard?.rankings.map(\.rank), [1, 2])
        XCTAssertEqual(arena.leaderboard?.myRank, 1)

        arena.undoRemoval()
        XCTAssertEqual(arena.leaderboard, original)
        XCTAssertEqual(arena.leaderboard?.myRank, 2)
    }

    // MARK: Requests and challenges

    func testDecliningARequestWaitsThenSendsTheDecline() async {
        arena.beginRemoval(ArenaRemoval(kind: .request, id: "r1"))
        XCTAssertEqual(arena.requests.map(\.id), ["r2"])
        XCTAssertEqual(calls("POST", containing: "decline"), 0)

        arena.finishRemoval()
        await wait { !self.arena.fetchedRequests.contains { $0.id == "r1" } }
        XCTAssertEqual(calls("POST", containing: "/v1/friends/requests/r1/decline"), 1)
        XCTAssertEqual(arena.requests.map(\.id), ["r2"])
    }

    func testLeavingAChallengeCanBeUndoneAndOtherwiseIsSentOnce() async {
        arena.beginRemoval(ArenaRemoval(kind: .challenge, id: "c1"))
        XCTAssertEqual(arena.challenges.map(\.id), ["c2"])
        arena.undoRemoval()
        XCTAssertEqual(arena.challenges.map(\.id), ["c1", "c2"])
        XCTAssertEqual(calls("POST", containing: "leave"), 0)

        arena.beginRemoval(ArenaRemoval(kind: .challenge, id: "c2"))
        arena.finishRemoval()
        await wait { !self.arena.fetchedChallenges.contains { $0.id == "c2" } }
        XCTAssertEqual(calls("POST", containing: "/v1/challenges/c2/leave"), 1)
        XCTAssertEqual(arena.challenges.map(\.id), ["c1"])
    }
}
