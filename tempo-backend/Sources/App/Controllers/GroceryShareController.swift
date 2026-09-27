import Fluent
import Foundation
import Vapor

// MARK: - GroceryShareController

//
// Owner-side (JWT authenticated) endpoints for the "live shared grocery
// list" feature. Mounted at /v1/grocery/shared by routes.swift.
//
//   PUT  /v1/grocery/shared               — create a share, or replace an
//                                            existing one's items (pass
//                                            `token` to target an existing
//                                            share; omit it to create one)
//   GET  /v1/grocery/shared/:token        — current state, incl. shopper ticks
//   POST /v1/grocery/shared/:token/revoke — turn the link off
//
// See PublicGroceryShareController for the public, unauthenticated /g/:token
// routes a shopper actually opens (no JWT, IP rate-limited).

struct GroceryShareController: RouteCollection {
    static let shareLifetime: TimeInterval = 14 * 24 * 3600
    static let maxItems = 500
    static let maxTextLength = 200

    func boot(routes: RoutesBuilder) throws {
        routes.put(use: createOrReplace)
        routes.get(":token", use: getState)
        routes.post(":token", "revoke", use: revoke)
    }

    // MARK: - PUT /

    @Sendable
    func createOrReplace(_ req: Request) async throws -> Envelope<GroceryShareDTO> {
        let userID = try req.auth.requireUserID()
        let input = try req.content.decode(GroceryShareUpsertRequest.self)
        try Self.validate(input)

        let now = Date()
        let share: SharedGroceryList
        var priorByID: [String: SharedGroceryItemSnapshot] = [:]

        if let token = input.token, !token.isEmpty {
            guard let existing = try await SharedGroceryList.query(on: req.db)
                .filter(\.$token == token)
                .filter(\.$userID == userID)
                .first()
            else {
                throw Abort(.notFound, reason: "Share not found.")
            }
            share = existing
            for item in existing.decodedItems() {
                priorByID[item.id] = item
            }
        } else {
            share = SharedGroceryList(
                userID: userID,
                token: String.randomHex(length: 20), // 160 bits
                title: input.title,
                store: input.store,
                itemsJSON: "[]",
                expiresAt: now.addingTimeInterval(Self.shareLifetime)
            )
        }

        share.title = input.title
        share.store = input.store
        // Sharing again after a revoke/expiry re-activates the SAME link
        // rather than forcing the owner to generate (and re-send) a new one.
        share.revoked = false
        share.expiresAt = now.addingTimeInterval(Self.shareLifetime)

        // Merge: catalog fields (name/quantity/unit/category) always take
        // the owner's incoming value — only the owner edits the list's
        // contents. `checked` is last-write-wins by `updated_at`: the
        // owner's own app only bumps an item's timestamp when ITS local
        // state actually changed since the last sync (see iOS
        // SharedGroceryListService), so a shopper's more recent tick
        // (server-stamped, see PublicGroceryShareController) is never
        // clobbered by a stale owner push that still carries an old
        // `checked` value at an old timestamp.
        let merged: [SharedGroceryItemSnapshot] = input.items.map { incoming in
            if let prior = priorByID[incoming.id], prior.updatedAt >= incoming.updatedAt {
                return SharedGroceryItemSnapshot(
                    id: incoming.id,
                    name: incoming.name,
                    quantity: incoming.quantity,
                    unit: incoming.unit,
                    category: incoming.category,
                    checked: prior.checked,
                    updatedAt: prior.updatedAt
                )
            }
            return SharedGroceryItemSnapshot(
                id: incoming.id,
                name: incoming.name,
                quantity: incoming.quantity,
                unit: incoming.unit,
                category: incoming.category,
                checked: incoming.checked,
                updatedAt: incoming.updatedAt
            )
        }
        share.itemsJSON = try SharedGroceryList.encodeItems(merged)

        try await share.save(on: req.db)

        return Envelope(
            data: GroceryShareDTO(share: share, items: merged, publicBaseURL: Self.publicBaseURL(req: req)),
            requestID: req.requestID
        )
    }

    // MARK: - GET /:token

    @Sendable
    func getState(_ req: Request) async throws -> Envelope<GroceryShareDTO> {
        let userID = try req.auth.requireUserID()
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest)
        }
        guard let share = try await SharedGroceryList.query(on: req.db)
            .filter(\.$token == token)
            .filter(\.$userID == userID)
            .first()
        else {
            throw Abort(.notFound)
        }
        return Envelope(
            data: GroceryShareDTO(share: share, items: share.decodedItems(), publicBaseURL: Self.publicBaseURL(req: req)),
            requestID: req.requestID
        )
    }

    // MARK: - POST /:token/revoke

    @Sendable
    func revoke(_ req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest)
        }
        guard let share = try await SharedGroceryList.query(on: req.db)
            .filter(\.$token == token)
            .filter(\.$userID == userID)
            .first()
        else {
            throw Abort(.notFound)
        }
        share.revoked = true
        try await share.save(on: req.db)
        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - Validation

    private static func validate(_ input: GroceryShareUpsertRequest) throws {
        guard
            !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            input.title.count <= maxTextLength
        else {
            throw Abort(.badRequest, reason: "title must be 1...\(maxTextLength) characters.")
        }
        if let store = input.store {
            guard store.count <= maxTextLength else {
                throw Abort(.badRequest, reason: "store must be at most \(maxTextLength) characters.")
            }
        }
        guard input.items.count <= maxItems else {
            throw Abort(.badRequest, reason: "A shared list can contain at most \(maxItems) items.")
        }
        for item in input.items {
            guard
                !item.id.trimmingCharacters(in: .whitespaces).isEmpty,
                item.id.count <= 64,
                !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                item.name.count <= maxTextLength,
                item.unit.count <= 40,
                item.category.count <= 40,
                item.quantity.isFinite, item.quantity >= 0
            else {
                throw Abort(.badRequest, reason: "Invalid item payload.")
            }
        }
        let ids = Set(input.items.map(\.id))
        guard ids.count == input.items.count else {
            throw Abort(.badRequest, reason: "Item ids must be unique.")
        }
    }

    // MARK: - Public base URL

    // Same pattern as ExerciseImageService.publicBaseURL(req:) — falls back
    // to deriving scheme+Host from the incoming request when unset, so local
    // dev/tests don't need the env var.

    static func publicBaseURL(req: Request) -> String {
        if let configured = Environment.get("PUBLIC_BASE_URL"), !configured.isEmpty {
            return configured
        }
        let scheme = req.headers.first(name: "X-Forwarded-Proto") ?? "https"
        let host = req.headers.first(name: .host) ?? "localhost:8080"
        return "\(scheme)://\(host)"
    }
}

// MARK: - DTOs

//
// Single-word properties (id/name/quantity/unit/category/checked/token/url/
// title/store/items/revoked) need no CodingKeys — they're identical before
// and after ContentConfiguration.global's snake_case conversion. `updatedAt`/
// `expiresAt` split cleanly too (updated_at -> updatedAt), so no explicit
// CodingKeys are needed anywhere in this file.

struct GroceryShareItemRequestDTO: Content {
    let id: String
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let checked: Bool
    let updatedAt: Date
}

struct GroceryShareUpsertRequest: Content {
    /// Present → replace that existing share's items. Absent/empty → create
    /// a new share.
    let token: String?
    let title: String
    let store: String?
    let items: [GroceryShareItemRequestDTO]
}

struct GroceryShareItemDTO: Content {
    let id: String
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let checked: Bool
    let updatedAt: Date

    init(_ snapshot: SharedGroceryItemSnapshot) {
        id = snapshot.id
        name = snapshot.name
        quantity = snapshot.quantity
        unit = snapshot.unit
        category = snapshot.category
        checked = snapshot.checked
        updatedAt = snapshot.updatedAt
    }
}

struct GroceryShareDTO: Content {
    let token: String
    let url: String
    let title: String
    let store: String?
    let items: [GroceryShareItemDTO]
    let expiresAt: Date
    let revoked: Bool

    init(share: SharedGroceryList, items: [SharedGroceryItemSnapshot], publicBaseURL: String) {
        token = share.token
        url = "\(publicBaseURL)/g/\(share.token)"
        title = share.title
        store = share.store
        self.items = items.map(GroceryShareItemDTO.init)
        expiresAt = share.expiresAt
        revoked = share.revoked
    }
}
