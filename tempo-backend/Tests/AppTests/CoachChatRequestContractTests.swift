@testable import App
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - "Ask Tempo" request contract (app -> server -> Claude)

//
// The bodies in `contracts/requests/` are what the iOS app really POSTs to
// /v1/nutrition/ai/coach/chat: its own test (CoachChatRequestContractTests in
// TempoTests) writes them from the app's encoder and fails if they drift.
// Here the same files go through the server:
//
//   1. the app's global JSON decoder (`.convertFromSnakeCase`) must read them,
//      explicit snake_case CodingKeys (`input_schema`, `tool_use_id`, `is_error`)
//      never match under that strategy, which made every chat message fail with
//      "Couldn't reach Coach";
//   2. what the server forwards to Anthropic must carry Anthropic's key names
//      (`max_tokens`, `tool_choice`, `input_schema`, `tool_use_id`, `is_error`)
//      and leave the free-form tool schema / tool input untouched;
//   3. the reply the app gets back keeps `stop_reason`, `usage`, and the camelCase
//      tool arguments (`mealID`, `newTimeHHmm`) exactly as Claude produced them.

@Suite("CoachChatRequestContract", .serialized)
struct CoachChatRequestContractTests {
    // MARK: - Fixtures

    private static var requestsDir: URL {
        // Tests/AppTests/<file> -> tempo-backend -> repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/requests", isDirectory: true)
    }

    private static func fixture(_ slug: String) throws -> Data {
        try Data(contentsOf: requestsDir.appendingPathComponent("\(slug).json"))
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Harness

    private func withApp(_ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        TestMode.force(true, on: app)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func login(_ app: Application) async throws -> String {
        var token = ""
        let name = "coach-\(UUID().uuidString.prefix(8).lowercased())"
        try await app.test(.POST, "v1/test/login", beforeRequest: { req in
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: "X-Device-Id", value: "coach-contract")
            req.body = ByteBuffer(string: #"{"name":"\#(name)"}"#)
        }, afterResponse: { res async throws in
            token = try res.content.decode(TestModeController.LoginResponse.self).accessToken
        })
        return token
    }

    private func postChat(_ app: Application, token: String, body: Data) async throws -> (status: HTTPStatus, json: [String: Any]) {
        var status = HTTPStatus.ok
        var json: [String: Any] = [:]
        try await app.test(.POST, "v1/nutrition/ai/coach/chat", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: token)
            req.headers.contentType = .json
            req.body = ByteBuffer(bytes: body)
        }, afterResponse: { res async throws in
            status = res.status
            json = (try? JSONSerialization.jsonObject(with: Data(res.body.readableBytesView)) as? [String: Any]) ?? [:]
        })
        return (status, json)
    }

    /// Stands in for api.anthropic.com: records the request body it is sent and
    /// answers with a canned Messages API reply.
    private final class AnthropicStub: Client, @unchecked Sendable {
        let eventLoop: EventLoop
        let reply: String
        private let lock: NSLock
        private let store: Store

        final class Store: @unchecked Sendable {
            var bodies: [Data] = []
        }

        init(eventLoop: EventLoop, reply: String, lock: NSLock = NSLock(), store: Store = Store()) {
            self.eventLoop = eventLoop
            self.reply = reply
            self.lock = lock
            self.store = store
        }

        var bodies: [Data] {
            lock.lock(); defer { lock.unlock() }
            return store.bodies
        }

        func delegating(to eventLoop: EventLoop) -> Client {
            AnthropicStub(eventLoop: eventLoop, reply: reply, lock: lock, store: store)
        }

        func logging(to _: Logger) -> Client {
            self
        }

        func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
            lock.lock()
            store.bodies.append(request.body.map { Data($0.readableBytesView) } ?? Data())
            lock.unlock()
            var headers = HTTPHeaders()
            headers.contentType = .json
            return eventLoop.makeSucceededFuture(ClientResponse(status: .ok, headers: headers, body: ByteBuffer(string: reply)))
        }
    }

    private static let toolUseReply = #"""
    {"id":"msg_01","type":"message","role":"assistant","model":"claude-haiku-4-5","content":[
      {"type":"text","text":"Moving it."},
      {"type":"tool_use","id":"toolu_01X","name":"moveMeal","input":{"mealID":"B5F0C2A4-0000-4000-8000-000000000001","newTimeHHmm":"20:30","snake_case_key":1}}
    ],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":1200,"output_tokens":85}}
    """#

    // MARK: - 1. The server reads what the app sends

    @Test func theAppsRequestsDecodeWithTheServersJSONConfiguration() async throws {
        try await withApp { _ in
            let decoder = try ContentConfiguration.global.requireDecoder(for: .json)
            func decode(_ slug: String) throws -> CoachProxyChatRequest {
                try decoder.decode(CoachProxyChatRequest.self, from: ByteBuffer(bytes: Self.fixture(slug)), headers: [:])
            }

            let conversation = try decode("coach-chat-conversation")
            #expect(conversation.model == "haiku")
            #expect(conversation.maxTokens == 800)
            #expect(conversation.toolChoice == nil)
            #expect(conversation.tools.count == 8)
            let schema = try #require(conversation.tools.first?.inputSchema.value as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            #expect(Set(properties.keys) == ["mealID", "newTimeHHmm"], "free-form schema keys must survive untouched")
            #expect(schema["required"] as? [String] == ["mealID", "newTimeHHmm"])

            #expect(conversation.messages.count == 4)
            guard case let .toolUse(id, name, input) = conversation.messages[1].content[1] else {
                Issue.record("message 1 block 1 should be a tool_use")
                return
            }
            #expect(id == "toolu_01A")
            #expect(name == "moveMeal")
            #expect(Set(input.keys) == ["mealID", "newTimeHHmm"])
            guard case let .toolResult(okID, _, okIsError) = conversation.messages[2].content[0],
                  case let .toolResult(failedID, _, failedIsError) = conversation.messages[2].content[1]
            else {
                Issue.record("message 2 should hold two tool_result blocks")
                return
            }
            #expect(okID == "toolu_01A" && !okIsError)
            #expect(failedID == "toolu_01B" && failedIsError, "is_error was dropped")

            let forced = try decode("coach-chat-forced-tool")
            guard case let .tool(forcedName) = try #require(forced.toolChoice) else {
                Issue.record("tool_choice should decode as .tool")
                return
            }
            #expect(forcedName == "askUser")
            #expect(forced.maxTokens == 512)
        }
    }

    // MARK: - 2. Through the real route, with the faked Claude

    @Test func theRouteAnswersWithTheTestModeFakeReply() async throws {
        try await withApp { app in
            let token = try await login(app)
            for slug in ["coach-chat-conversation", "coach-chat-forced-tool"] {
                let (status, json) = try await postChat(app, token: token, body: Self.fixture(slug))
                #expect(status == .ok, "\(slug) -> \(status) \(json)")
                let data = try #require(json["data"] as? [String: Any])
                #expect(data["stop_reason"] as? String == "end_turn")
                let content = try #require(data["content"] as? [[String: Any]])
                #expect((content.first?["text"] as? String)?.hasPrefix("Copy that.") == true)
            }
        }
    }

    // MARK: - 3. What Anthropic receives, and what the app gets back

    @Test func theUpstreamBodyUsesAnthropicKeysAndLeavesFreeFormJSONAlone() async throws {
        try await withApp { app in
            let stub = AnthropicStub(eventLoop: app.eventLoopGroup.next(), reply: Self.toolUseReply)
            app.clients.use { _ in stub }
            let token = try await login(app)

            // Conversation: tools + tool_use history + tool_result turns.
            let (status, json) = try await postChat(app, token: token, body: Self.fixture("coach-chat-conversation"))
            #expect(status == .ok, "\(status) \(json)")

            let upstreamData = try #require(stub.bodies.last)
            let upstreamText = String(decoding: upstreamData, as: UTF8.self)
            for appKey in ["inputSchema", "toolUseId", "toolUseID", "isError", "maxTokens", "toolChoice"] {
                #expect(!upstreamText.contains("\"\(appKey)\""), "upstream body leaked the app-side key \(appKey)")
            }
            let upstream = try Self.object(upstreamData)
            #expect(Set(upstream.keys) == ["model", "max_tokens", "system", "messages", "tools"])
            #expect(upstream["model"] as? String == AIConfig.haikuModel)
            #expect(upstream["max_tokens"] as? Int == 800)

            let tools = try #require(upstream["tools"] as? [[String: Any]])
            #expect(tools.count == 8)
            for tool in tools {
                #expect(Set(tool.keys) == ["name", "description", "input_schema"])
            }
            let firstSchema = try #require(tools[0]["input_schema"] as? [String: Any])
            #expect(firstSchema["type"] as? String == "object")
            let firstProperties = try #require(firstSchema["properties"] as? [String: Any])
            #expect(Set(firstProperties.keys) == ["mealID", "newTimeHHmm"])
            #expect(firstSchema["required"] as? [String] == ["mealID", "newTimeHHmm"])

            let messages = try #require(upstream["messages"] as? [[String: Any]])
            let toolUse = try #require((messages[1]["content"] as? [[String: Any]])?[1])
            #expect(toolUse["type"] as? String == "tool_use")
            let toolInput = try #require(toolUse["input"] as? [String: Any])
            #expect(toolInput["mealID"] as? String == "B5F0C2A4-0000-4000-8000-000000000001")
            #expect(toolInput["newTimeHHmm"] as? String == "20:30")

            let results = try #require(messages[2]["content"] as? [[String: Any]])
            #expect(results[0]["type"] as? String == "tool_result")
            #expect(results[0]["tool_use_id"] as? String == "toolu_01A")
            #expect(results[0]["is_error"] == nil, "a successful result must not be flagged")
            #expect(results[1]["tool_use_id"] as? String == "toolu_01B")
            #expect(results[1]["is_error"] as? Bool == true)

            // What the app gets back.
            let data = try #require(json["data"] as? [String: Any])
            #expect(json["ok"] as? Bool == true)
            #expect(data["stop_reason"] as? String == "tool_use")
            #expect(data["model"] as? String == AIConfig.haikuModel)
            let usage = try #require(data["usage"] as? [String: Any])
            #expect(usage["input_tokens"] as? Int == 1200)
            #expect(usage["output_tokens"] as? Int == 85)
            let content = try #require(data["content"] as? [[String: Any]])
            #expect(content.count == 2)
            #expect(content[1]["type"] as? String == "tool_use")
            #expect(content[1]["id"] as? String == "toolu_01X")
            let replyInput = try #require(content[1]["input"] as? [String: Any])
            #expect(replyInput["mealID"] as? String == "B5F0C2A4-0000-4000-8000-000000000001")
            #expect(replyInput["newTimeHHmm"] as? String == "20:30")
            #expect(replyInput["snake_case_key"] as? Int == 1, "tool arguments must reach the app exactly as Claude wrote them")
        }
    }

    @Test func aForcedToolChoiceReachesAnthropicWithItsOwnKeys() async throws {
        try await withApp { app in
            let stub = AnthropicStub(eventLoop: app.eventLoopGroup.next(), reply: Self.toolUseReply)
            app.clients.use { _ in stub }
            let token = try await login(app)

            let (status, json) = try await postChat(app, token: token, body: Self.fixture("coach-chat-forced-tool"))
            #expect(status == .ok, "\(status) \(json)")

            let upstream = try Self.object(#require(stub.bodies.last))
            #expect(upstream["model"] as? String == AIConfig.sonnetModel)
            #expect(upstream["max_tokens"] as? Int == 512)
            let choice = try #require(upstream["tool_choice"] as? [String: Any])
            #expect(choice["type"] as? String == "tool")
            #expect(choice["name"] as? String == "askUser")
            #expect(upstream["toolChoice"] == nil)
        }
    }
}
