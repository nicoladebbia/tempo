import Vapor
import Fluent

// MARK: - Friend Controller
// Per BACKEND_API.md Section 10.6 — Friend system endpoints.
// Per STATE_MACHINES.md Section 9 — Friend Request state machine.

struct FriendController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        // Friend requests
        routes.post("requests", use: sendRequest)
        routes.get("requests", use: listRequests)
        routes.post("requests", ":requestID", "accept", use: acceptRequest)
        routes.post("requests", ":requestID", "decline", use: declineRequest)

        // Friends list and management
        routes.get(use: listFriends)
        routes.delete(":friendshipID", use: removeFriend)
    }

    // MARK: - POST /v1/friends/requests
    // Per BACKEND_API.md Section 10.6 — Send friend request.
    // Per STATE_MACHINES.md Section 9 — none -> pendingSent transition.

    @Sendable
    func sendRequest(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(FriendRequestDTO.self)

        // Cannot befriend yourself
        guard body.userID != userID else {
            throw Abort(.badRequest, reason: "Cannot send a friend request to yourself.")
        }

        // Verify target user exists
        guard let _ = try await User.find(body.userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        // Check if already friends
        let existingFriendship = try await findFriendship(userA: userID, userB: body.userID, on: req.db)
        guard existingFriendship == nil else {
            throw Abort(.conflict, reason: "Already friends.")
        }

        // Check for existing pending request
        let existingRequest = try await FriendRequest.query(on: req.db)
            .group(.or) { group in
                group.group(.and) { and in
                    and.filter(\.$fromUserID == userID)
                    and.filter(\.$toUserID == body.userID)
                }
                group.group(.and) { and in
                    and.filter(\.$fromUserID == body.userID)
                    and.filter(\.$toUserID == userID)
                }
            }
            .filter(\.$status == "pending")
            .first()

        guard existingRequest == nil else {
            throw Abort(.conflict, reason: "Friend request already pending.")
        }

        let friendRequest = FriendRequest(fromUserID: userID, toUserID: body.userID)
        try await friendRequest.save(on: req.db)

        let response = Envelope(
            data: FriendRequestResponseDTO(
                id: friendRequest.id?.uuidString ?? "",
                fromUserID: friendRequest.fromUserID,
                toUserID: friendRequest.toUserID,
                status: friendRequest.status,
                createdAt: friendRequest.createdAt ?? Date()
            ),
            requestID: req.requestID
        )

        let encoded = try Response(
            status: .created,
            headers: ["Content-Type": "application/json"],
            body: .init(data: JSONEncoder.apiEncoder.encode(response))
        )
        return encoded
    }

    // MARK: - GET /v1/friends/requests
    // Per BACKEND_API.md Section 10.6 — List pending friend requests.

    @Sendable
    func listRequests(req: Request) async throws -> Envelope<[FriendRequestResponseDTO]> {
        let userID = try req.auth.requireUserID()

        let requests = try await FriendRequest.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$fromUserID == userID)
                group.filter(\.$toUserID == userID)
            }
            .filter(\.$status == "pending")
            .sort(\.$createdAt, .descending)
            .all()

        let dtos = requests.map { r in
            FriendRequestResponseDTO(
                id: r.id?.uuidString ?? "",
                fromUserID: r.fromUserID,
                toUserID: r.toUserID,
                status: r.status,
                createdAt: r.createdAt ?? Date()
            )
        }

        return Envelope(data: dtos, requestID: req.requestID)
    }

    // MARK: - POST /v1/friends/requests/:id/accept
    // Per STATE_MACHINES.md Section 9 — pendingReceived -> accepted transition.

    @Sendable
    func acceptRequest(req: Request) async throws -> Envelope<FriendshipResponseDTO> {
        let userID = try req.auth.requireUserID()
        guard let requestIDString = req.parameters.get("requestID"),
              let requestID = UUID(uuidString: requestIDString) else {
            throw Abort(.badRequest, reason: "Valid request ID required.")
        }

        guard let friendRequest = try await FriendRequest.find(requestID, on: req.db) else {
            throw Abort(.notFound, reason: "Friend request not found.")
        }

        // Only the recipient can accept
        guard friendRequest.toUserID == userID else {
            throw Abort(.forbidden, reason: "Only the recipient can accept a friend request.")
        }

        guard friendRequest.status == "pending" else {
            throw Abort(.conflict, reason: "Request is no longer pending.")
        }

        // Update request
        friendRequest.status = "accepted"
        friendRequest.respondedAt = Date()
        try await friendRequest.save(on: req.db)

        // Create friendship
        let friendship = Friendship(userAID: friendRequest.fromUserID, userBID: friendRequest.toUserID)
        try await friendship.save(on: req.db)

        return Envelope(
            data: FriendshipResponseDTO(
                id: friendship.id?.uuidString ?? "",
                userID: friendRequest.fromUserID,
                createdAt: friendship.createdAt ?? Date()
            ),
            requestID: req.requestID
        )
    }

    // MARK: - POST /v1/friends/requests/:id/decline
    // Per STATE_MACHINES.md Section 9 — pendingReceived -> declined transition.

    @Sendable
    func declineRequest(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let requestIDString = req.parameters.get("requestID"),
              let requestID = UUID(uuidString: requestIDString) else {
            throw Abort(.badRequest, reason: "Valid request ID required.")
        }

        guard let friendRequest = try await FriendRequest.find(requestID, on: req.db) else {
            throw Abort(.notFound, reason: "Friend request not found.")
        }

        guard friendRequest.toUserID == userID else {
            throw Abort(.forbidden, reason: "Only the recipient can decline a friend request.")
        }

        guard friendRequest.status == "pending" else {
            throw Abort(.conflict, reason: "Request is no longer pending.")
        }

        friendRequest.status = "declined"
        friendRequest.respondedAt = Date()
        try await friendRequest.save(on: req.db)

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - GET /v1/friends
    // Per BACKEND_API.md Section 10.6 — List friends.

    @Sendable
    func listFriends(req: Request) async throws -> Envelope<[FriendDTO]> {
        let userID = try req.auth.requireUserID()

        let friendships = try await Friendship.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$userAID == userID)
                group.filter(\.$userBID == userID)
            }
            .sort(\.$createdAt, .descending)
            .all()

        var friends: [FriendDTO] = []
        for friendship in friendships {
            let friendID = friendship.userAID == userID ? friendship.userBID : friendship.userAID
            if let user = try await User.find(friendID, on: req.db) {
                friends.append(FriendDTO(
                    friendshipID: friendship.id?.uuidString ?? "",
                    userID: user.id ?? "",
                    username: user.username,
                    displayName: user.displayName,
                    level: user.level,
                    streakDays: user.streakDays,
                    friendsSince: friendship.createdAt ?? Date()
                ))
            }
        }

        return Envelope(data: friends, requestID: req.requestID)
    }

    // MARK: - DELETE /v1/friends/:friendshipID
    // Per STATE_MACHINES.md Section 9 — accepted -> none transition.

    @Sendable
    func removeFriend(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let friendshipIDString = req.parameters.get("friendshipID"),
              let friendshipID = UUID(uuidString: friendshipIDString) else {
            throw Abort(.badRequest, reason: "Valid friendship ID required.")
        }

        guard let friendship = try await Friendship.find(friendshipID, on: req.db) else {
            throw Abort(.notFound, reason: "Friendship not found.")
        }

        // Must be one of the two friends
        guard friendship.userAID == userID || friendship.userBID == userID else {
            throw Abort(.forbidden, reason: "Not your friendship.")
        }

        try await friendship.delete(on: req.db)

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - Helpers

    private func findFriendship(userA: String, userB: String, on db: Database) async throws -> Friendship? {
        let (a, b) = userA < userB ? (userA, userB) : (userB, userA)
        return try await Friendship.query(on: db)
            .filter(\.$userAID == a)
            .filter(\.$userBID == b)
            .first()
    }
}

// MARK: - DTOs

struct FriendRequestDTO: Content {
    let userID: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

struct FriendRequestResponseDTO: Content {
    let id: String
    let fromUserID: String
    let toUserID: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case fromUserID = "from_user_id"
        case toUserID = "to_user_id"
        case createdAt = "created_at"
    }
}

struct FriendshipResponseDTO: Content {
    let id: String
    let userID: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct FriendDTO: Content {
    let friendshipID: String
    let userID: String
    let username: String
    let displayName: String
    let level: Int
    let streakDays: Int
    let friendsSince: Date

    enum CodingKeys: String, CodingKey {
        case username, level
        case friendshipID = "friendship_id"
        case userID = "user_id"
        case displayName = "display_name"
        case streakDays = "streak_days"
        case friendsSince = "friends_since"
    }
}

// MARK: - JSON Encoder Extension

extension JSONEncoder {
    static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}
