import Foundation
import NIOCore
import Vapor

// MARK: - TestModeClient

//
// Replaces `app.client` (and so every `req.client`) in test mode. Answers by
// host; anything unknown gets a 502 and a log line instead of a real request,
// so a QA session never calls a paid or rate-limited service by accident.
// Only Claude can go out for real, and only in AI mode `.real`.

struct TestModeClient: Client {
    let eventLoop: EventLoop
    let state: TestModeState
    let real: Client
    let logger: Logger

    static var hasRealAnthropicKey: Bool {
        guard let key = Environment.get("ANTHROPIC_API_KEY") else { return false }
        return key.hasPrefix("sk-ant-")
    }

    func delegating(to eventLoop: EventLoop) -> Client {
        TestModeClient(eventLoop: eventLoop, state: state, real: real, logger: logger)
    }

    func logging(to logger: Logger) -> Client {
        TestModeClient(eventLoop: eventLoop, state: state, real: real, logger: logger)
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        let promise = eventLoop.makePromise(of: ClientResponse.self)
        promise.completeWithTask {
            try await self.respond(to: request)
        }
        return promise.futureResult
    }

    // MARK: - Routing

    func respond(to request: ClientRequest) async throws -> ClientResponse {
        let host = request.url.host ?? ""
        let path = request.url.path
        switch host {
        case "api.anthropic.com":
            return try await anthropic(request)
        case "api.nal.usda.gov":
            return Self.json(TestFixtures.usdaSearch(query: Self.queryValue("query", in: request.url) ?? ""))
        case "world.openfoodfacts.org":
            return Self.json(TestFixtures.openFoodFactsProduct(path: path))
        case "api.ods.od.nih.gov":
            return Self.json(path.contains("/label/") ? TestFixtures.dsldLabel : TestFixtures.dsldSearch)
        case "api.openai.com":
            return Self.json(TestFixtures.openAIImage)
        case "api.prod.whoop.com":
            return Self.json(TestFixtures.whoop(path: path))
        default:
            if host.contains("instacart") {
                return Self.json(#"{"products_link_url":"https://www.instacart.com/store/recipes/test-mode-list"}"#)
            }
            logger.warning("[test-mode] blocked outbound \(request.method.rawValue) \(host)\(path) — add a fixture in TestModeClient")
            return Self.json(#"{"error":"blocked by Tempo test mode"}"#, status: .badGateway)
        }
    }

    private func anthropic(_ request: ClientRequest) async throws -> ClientResponse {
        let bodyText = request.body.map { String(buffer: $0) } ?? ""
        let context = TestFixtures.context(fromRequestBody: bodyText)
        let feature = TestFixtures.claudeFeature(for: context)
        let mode = state.aiMode
        func done(_ response: ClientResponse) -> ClientResponse {
            state.record(AICallRecord(at: Date(), feature: feature.name, mode: mode.rawValue, status: Int(response.status.code)))
            logger.info("[test-mode] Claude \(feature.name) → \(mode.rawValue) (\(response.status.code))")
            return response
        }

        switch mode {
        case .real:
            guard Self.hasRealAnthropicKey else {
                return done(Self.json(TestFixtures.anthropicError(type: "authentication_error", message: "test mode has no real key"), status: .unauthorized))
            }
            return try done(await real.delegating(to: eventLoop).send(request).get())
        case .error:
            return done(Self.json(TestFixtures.anthropicError(type: "overloaded_error", message: "Overloaded (test mode)"), status: .init(statusCode: 529)))
        case .empty:
            return done(Self.json(TestFixtures.anthropicMessage(text: "", model: feature.model)))
        case .broken:
            return done(Self.json(TestFixtures.anthropicMessage(text: feature.broken, model: feature.model)))
        case .slow:
            try await Task.sleep(nanoseconds: UInt64(state.slowSeconds * 1_000_000_000))
            return done(Self.json(TestFixtures.anthropicMessage(text: feature.reply(context), model: feature.model)))
        case .fake:
            return done(Self.json(TestFixtures.anthropicMessage(text: feature.reply(context), model: feature.model)))
        }
    }

    // MARK: - Helpers

    static func json(_ body: String, status: HTTPResponseStatus = .ok) -> ClientResponse {
        var headers = HTTPHeaders()
        headers.contentType = .json
        return ClientResponse(status: status, headers: headers, body: ByteBuffer(string: body))
    }

    static func queryValue(_ name: String, in url: URI) -> String? {
        guard let query = url.query else { return nil }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.first.map(String.init) == name, parts.count == 2 {
                return String(parts[1]).removingPercentEncoding
            }
        }
        return nil
    }
}
