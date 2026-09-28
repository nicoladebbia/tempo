import Foundation
import Vapor

// MARK: - InstacartClient

//
// Protocol seam for the Instacart Developer Platform (IDP) "create shopping
// list page" endpoint (POST /idp/v1/products/products_link), so tests can
// stub the outbound HTTP call — same shape as USDAFoodClient/USDAAPIClient.
// Per docs.instacart.com/developer_platform_api/api/products/create_shopping_list_page.

protocol InstacartClient: Sendable {
    func createShoppingListLink(
        title: String,
        items: [InstacartCartItemDTO],
        apiKey: String,
        on req: Request
    ) async throws -> String
}

enum InstacartClientError: Error, Equatable {
    case upstreamError(UInt)
    case malformedResponse
}

struct InstacartAPIClient: InstacartClient {
    func createShoppingListLink(
        title: String,
        items: [InstacartCartItemDTO],
        apiKey: String,
        on req: Request
    ) async throws -> String {
        let base = Environment.get("INSTACART_API_BASE") ?? "https://connect.instacart.com"
        let uri = URI(string: "\(base)/idp/v1/products/products_link")

        // Instacart's own wire format (snake_case, fixed by their API) — built
        // as a raw dictionary + JSONSerialization rather than a Content type,
        // deliberately sidestepping ContentConfiguration.global so this
        // third-party payload's casing can never drift with our own.
        let lineItems: [[String: Any]] = items.map { item in
            var dict: [String: Any] = ["name": item.name]
            if let quantity = item.quantity {
                dict["quantity"] = quantity
            }
            if let unit = item.unit, !unit.isEmpty {
                dict["unit"] = unit
            }
            return dict
        }
        let body: [String: Any] = [
            "title": title,
            "link_type": "shopping_list",
            "line_items": lineItems,
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let response = try await req.client.post(uri) { outgoing in
            outgoing.headers.bearerAuthorization = BearerAuthorization(token: apiKey)
            outgoing.headers.contentType = .json
            outgoing.body = .init(data: bodyData)
        }

        guard response.status == .ok || response.status == .created else {
            req.logger.error("Instacart products_link HTTP \(response.status.code)")
            throw InstacartClientError.upstreamError(response.status.code)
        }
        guard let decoded = try? response.content.decode(InstacartLinkResponse.self) else {
            throw InstacartClientError.malformedResponse
        }
        return decoded.productsLinkUrl
    }
}

/// Wire key is `products_link_url`; ContentConfiguration.global's
/// `.convertFromSnakeCase` turns that into `productsLinkUrl` before key
/// matching, which already equals this property name — no CodingKeys needed.
struct InstacartLinkResponse: Content {
    let productsLinkUrl: String
}
