import Vapor

// MARK: - InstacartController

//
// POST /v1/grocery/instacart-cart — turns the caller's grocery list into an
// Instacart "shopping list" page URL via the Instacart Developer Platform
// (IDP). The API key never leaves the server (INSTACART_API_KEY env var).
// When the key isn't configured, returns a typed `instacart_not_configured`
// error so the app can fall back to per-item search links instead of a raw
// 500. See docs.instacart.com/developer_platform_api.

struct InstacartController: RouteCollection {
    let instacartClient: InstacartClient

    init(instacartClient: InstacartClient = InstacartAPIClient()) {
        self.instacartClient = instacartClient
    }

    func boot(routes: RoutesBuilder) throws {
        routes.post("instacart-cart", use: createCart)
    }

    @Sendable
    func createCart(_ req: Request) async throws -> Envelope<InstacartCartResponseDTO> {
        _ = try req.auth.requireUserID()
        let input = try req.content.decode(InstacartCartRequest.self)
        guard !input.items.isEmpty, input.items.count <= 200 else {
            throw Abort(.badRequest, reason: "items must contain 1...200 entries.")
        }
        for item in input.items {
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.name.count <= 200 else {
                throw Abort(.badRequest, reason: "Invalid item name.")
            }
        }

        guard let apiKey = Environment.get("INSTACART_API_KEY"), !apiKey.isEmpty else {
            throw Abort(
                .preconditionFailed,
                reason: "Instacart ordering isn't configured on this server yet.",
                identifier: "instacart_not_configured"
            )
        }

        do {
            let url = try await instacartClient.createShoppingListLink(
                title: input.title ?? "Tempo Grocery List",
                items: input.items,
                apiKey: apiKey,
                on: req
            )
            return Envelope(data: InstacartCartResponseDTO(url: url), requestID: req.requestID)
        } catch let InstacartClientError.upstreamError(status) where status == 429 {
            throw Abort(.tooManyRequests, reason: "Instacart is busy. Try again shortly.")
        } catch {
            req.logger.error("Instacart cart creation failed: \(error)")
            throw Abort(.badGateway, reason: "Couldn't reach Instacart. Try again shortly.")
        }
    }
}

// MARK: - DTOs

struct InstacartCartItemDTO: Content {
    let name: String
    let quantity: Double?
    let unit: String?
}

struct InstacartCartRequest: Content {
    let title: String?
    let items: [InstacartCartItemDTO]
}

struct InstacartCartResponseDTO: Content {
    let url: String
}
