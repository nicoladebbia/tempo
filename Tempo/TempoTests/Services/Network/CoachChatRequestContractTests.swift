//
// CoachChatRequestContractTests.swift
// Tempo
//
// App -> server contract for "Ask Tempo": the exact JSON the app POSTs to
// /v1/nutrition/ai/coach/chat, pinned in contracts/requests/*.json. The backend
// test CoachChatRequestContractTests posts the same files through the real
// route, so a key the app renames (or the server stops accepting) fails a test
// instead of showing "Couldn't reach Coach" on a phone. See contracts/README.md.
//
// The bodies are produced by the app's real code: the first through
// CoachChatAIClientAdapter (history, tool_use / tool_result turns, the shipped
// tool catalog), the second straight from the proxy DTO with a forced tool.
//
// Regenerate after an intended change to the request shape:
//   TEST_RUNNER_TEMPO_UPDATE_CONTRACTS=1 scripts/sim.sh test -only-testing:TempoTests/CoachChatRequestContractTests
//

@testable import Tempo
import XCTest

final class CoachChatRequestContractTests: XCTestCase {
    // MARK: - Helpers

    private final class CapturingRequester: APIRequester, @unchecked Sendable {
        var lastBody: Data?

        func request<Response: Decodable & Sendable>(
            _: APIEndpoint<Response>,
            body: some Encodable & Sendable
        ) async throws -> Response {
            // Same encoder settings as APIClient: no key strategy, ISO-8601 dates.
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            lastBody = try encoder.encode(body)
            throw CancellationError()
        }
    }

    private static var requestsDir: URL {
        // TempoTests/Services/Network/<file> -> repo root
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("contracts/requests", isDirectory: true)
    }

    private static var updating: Bool {
        ProcessInfo.processInfo.environment["TEMPO_UPDATE_CONTRACTS"] == "1"
    }

    /// Sorted, pretty-printed, so the file only changes when the shape does.
    private func canonical(_ body: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: body)
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private func assertMatchesFixture(
        _ slug: String, _ body: Data,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let canonicalBody = try canonical(body)
        let url = Self.requestsDir.appendingPathComponent("\(slug).json")
        if Self.updating {
            try FileManager.default.createDirectory(at: Self.requestsDir, withIntermediateDirectories: true)
            try canonicalBody.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let existing = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(
            existing, canonicalBody,
            "contracts/requests/\(slug).json differs from what the app now sends. If intended, regenerate it (see the header of this file) and make the backend CoachChatRequestContractTests pass.",
            file: file, line: line
        )
    }

    // MARK: - Tests

    /// A full agent-loop turn: user text, an assistant turn with text + tool_use
    /// (camelCase tool args), the user turn that answers it with one ok and one
    /// failed tool_result, then the new user message. Plus the whole tool catalog.
    func testConversationRequestMatchesFixture() async throws {
        let requester = CapturingRequester()
        let adapter = CoachChatAIClientAdapter(requester: requester)
        let history = [
            CoachMessage(role: "user", text: "Move dinner to 8:30pm"),
            CoachMessage(
                role: "assistant",
                text: "Moving it.",
                toolCalls: [PendingToolCall(
                    id: "toolu_01A",
                    name: "moveMeal",
                    inputJSON: Data(#"{"mealID":"B5F0C2A4-0000-4000-8000-000000000001","newTimeHHmm":"20:30"}"#.utf8)
                )]
            ),
            CoachMessage(role: "user", toolResults: [
                ToolResult(toolUseID: "toolu_01A", outputText: "Moved dinner 19:30 -> 20:30", isError: false),
                ToolResult(toolUseID: "toolu_01B", outputText: "Meal not found", isError: true),
            ]),
            CoachMessage(role: "user", text: "Thanks, and skip lunch tomorrow"),
        ]
        let request = CoachChatRequest(systemPrompt: "You are Tempo's coach.", history: history, model: .haiku)

        _ = try? await adapter.sendChat(request: request)

        try assertMatchesFixture("coach-chat-conversation", XCTUnwrap(requester.lastBody))
    }

    /// `tool_choice` forcing one named tool (the adapter doesn't set it today,
    /// but the wire DTO and the server both support it).
    func testForcedToolChoiceRequestMatchesFixture() throws {
        let request = CoachChatProxyRequest(
            model: "sonnet",
            maxTokens: 512,
            system: "Extract the preference.",
            messages: [CoachChatProxyMessage(role: "user", content: [.text("No fish on weekdays")])],
            tools: [CoachToolCatalog.defaultCatalog[5]],
            toolChoice: .tool(name: "askUser")
        )
        try assertMatchesFixture("coach-chat-forced-tool", JSONEncoder().encode(request))
    }

    func testRequestFixturesAreExactlyTheOnesTheBackendPosts() throws {
        // The backend test iterates this directory; keep the list explicit so a
        // stray file can't be skipped silently on either side.
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.requestsDir.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        if Self.updating {
            return
        }
        XCTAssertEqual(names, ["coach-chat-conversation.json", "coach-chat-forced-tool.json"])
    }
}
