import Fluent
import Foundation
import Vapor

// MARK: - PublicGroceryShareController

//
// Public, UNAUTHENTICATED endpoints for a shared grocery list — mounted
// directly on `app` at /g (not under /v1, no JWT) by routes.swift, so the
// link is short enough to text someone. IP rate-limited (RateLimitMiddleware),
// same middleware the rest of the app uses for IP-scoped routes.
//
//   GET  /g/:token            — self-contained HTML page (inline CSS/JS)
//   GET  /g/:token/state      — JSON state, polled by the page's own JS
//   POST /g/:token/items/:id  — set (or toggle, if no body) one item's checked state
//
// No owner PII is ever exposed here — GroceryShareDTO only carries token,
// title, store and items, never the owning user's id/name/email.

struct PublicGroceryShareController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get(":token", use: page)
        routes.get(":token", "state", use: state)
        routes.post(":token", "items", ":itemID", use: toggleItem)
    }

    // MARK: - GET /g/:token

    @Sendable
    func page(_ req: Request) async throws -> Response {
        guard
            let token = req.parameters.get("token"),
            let share = try await SharedGroceryList.query(on: req.db)
            .filter(\.$token == token)
            .first(),
            share.isLive
        else {
            return Self.goneResponse()
        }
        let html = SharedGroceryPageRenderer.render(title: share.title, store: share.store, token: token)
        let response = Response(status: .ok, body: .init(string: html))
        response.headers.contentType = .html
        return response
    }

    // MARK: - GET /g/:token/state

    @Sendable
    func state(_ req: Request) async throws -> Envelope<GroceryShareDTO> {
        let share = try await Self.requireLiveShare(token: req.parameters.get("token"), on: req.db)
        return Envelope(
            data: GroceryShareDTO(share: share, items: share.decodedItems(), publicBaseURL: GroceryShareController.publicBaseURL(req: req)),
            requestID: req.requestID
        )
    }

    // MARK: - POST /g/:token/items/:itemID

    @Sendable
    func toggleItem(_ req: Request) async throws -> Envelope<GroceryShareItemDTO> {
        let share = try await Self.requireLiveShare(token: req.parameters.get("token"), on: req.db)
        guard let itemID = req.parameters.get("itemID"), itemID.count <= 64 else {
            throw Abort(.badRequest)
        }
        let body = try? req.content.decode(ToggleItemRequest.self)

        var items = share.decodedItems()
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            throw Abort(.notFound, reason: "Item not found.")
        }

        // Server-authoritative timestamp: this is a public, unauthenticated
        // endpoint, so the caller's clock is never trusted for the LWW merge
        // (a malicious client could otherwise backdate/future-date a tick to
        // always win or always lose against the owner's app).
        let newChecked = body?.checked ?? !items[index].checked
        items[index].checked = newChecked
        items[index].updatedAt = Date()

        share.itemsJSON = try SharedGroceryList.encodeItems(items)
        try await share.save(on: req.db)

        return Envelope(data: GroceryShareItemDTO(items[index]), requestID: req.requestID)
    }

    // MARK: - Helpers

    /// Unknown token and expired/revoked-but-real token must be
    /// indistinguishable to the caller (both 410) — otherwise `/state` and
    /// `/items/:id` become an oracle a caller could use to enumerate which
    /// tokens ever existed, even though `page()` already hides that
    /// distinction behind a single generic "gone" response.
    private static func requireLiveShare(token: String?, on db: any Database) async throws -> SharedGroceryList {
        guard
            let token,
            let share = try await SharedGroceryList.query(on: db)
            .filter(\.$token == token)
            .first(),
            share.isLive
        else {
            throw Abort(.gone, reason: "This shared list has expired or was revoked.")
        }
        return share
    }

    private static func goneResponse() -> Response {
        let html = SharedGroceryPageRenderer.renderGone()
        let response = Response(status: .gone, body: .init(string: html))
        response.headers.contentType = .html
        return response
    }
}

struct ToggleItemRequest: Content {
    let checked: Bool?
}
