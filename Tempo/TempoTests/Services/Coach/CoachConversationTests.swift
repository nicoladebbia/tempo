//
// CoachConversationTests.swift
// Tempo
//
// Coach v2.1 Phase 6a — covers CoachConversation persistence, the
// JSON-blob ↔ [CoachMessage] round-trip, the append + collapse helpers,
// and lastMessageAt advancement.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachConversationTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CoachConversation.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Round-trip

    func testMessagesAccessor_emptyInitialState() {
        let conv = CoachConversation()
        XCTAssertEqual(conv.messages.count, 0)
        XCTAssertEqual(conv.messagesJSON, Data())
    }

    func testMessagesAccessor_seedFromInit() {
        let now = Date()
        let messages = [
            CoachMessage(role: "user", text: "hello", timestamp: now),
            CoachMessage(role: "assistant", text: "hi back", timestamp: now.addingTimeInterval(1)),
        ]
        let conv = CoachConversation(messages: messages)
        XCTAssertEqual(conv.messages.count, 2)
        XCTAssertEqual(conv.messages.first?.text, "hello")
        XCTAssertEqual(conv.messages.last?.text, "hi back")
    }

    func testMessagesAccessor_writeAdvancesLastMessageAt() {
        let conv = CoachConversation()
        let originalLast = conv.lastMessageAt
        let later = Date(timeIntervalSince1970: originalLast.timeIntervalSince1970 + 10)
        conv.messages = [
            CoachMessage(role: "user", text: "now", timestamp: later),
        ]
        XCTAssertEqual(conv.lastMessageAt, later)
    }

    // MARK: - SwiftData round-trip

    func testPersistsAndDecodesMessagesAcrossFetch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let conv = CoachConversation(
            id: id,
            messages: [
                CoachMessage(role: "user", text: "soccer at 7pm", timestamp: Date()),
                CoachMessage(role: "assistant", text: "got it", timestamp: Date(), model: "haiku"),
            ]
        )
        context.insert(conv)
        try context.save()

        let descriptor = FetchDescriptor<CoachConversation>(
            predicate: #Predicate<CoachConversation> { $0.id == id }
        )
        let fetched = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertEqual(fetched.messages.count, 2)
        XCTAssertEqual(fetched.messages.first?.role, "user")
        XCTAssertEqual(fetched.messages.last?.model, "haiku")
    }

    // MARK: - append

    func testAppend_addsMessage() {
        let conv = CoachConversation()
        conv.append(CoachMessage(role: "user", text: "one"))
        XCTAssertEqual(conv.messages.count, 1)
        conv.append(CoachMessage(role: "assistant", text: "two"))
        XCTAssertEqual(conv.messages.count, 2)
        XCTAssertEqual(conv.messages.last?.text, "two")
    }

    // MARK: - collapseEarlyMessages

    func testCollapse_replacesPrefixWithSummary() {
        let conv = CoachConversation()
        for i in 0..<6 {
            conv.append(CoachMessage(role: "user", text: "msg \(i)", timestamp: Date().addingTimeInterval(TimeInterval(i))))
        }
        let summary = CoachMessage(
            role: "system_summary",
            text: "Earlier: discussed soccer night dinner shift.",
            timestamp: conv.messages.first!.timestamp
        )
        conv.collapseEarlyMessages(upTo: 3, with: summary)
        XCTAssertEqual(conv.messages.count, 4) // 1 summary + 3 preserved
        XCTAssertEqual(conv.messages.first?.role, "system_summary")
        XCTAssertEqual(conv.messages.dropFirst().first?.text, "msg 3")
    }

    func testCollapse_upToExceedsCount_replacesEverything() {
        let conv = CoachConversation()
        conv.append(CoachMessage(role: "user", text: "only"))
        let summary = CoachMessage(role: "system_summary", text: "all")
        conv.collapseEarlyMessages(upTo: 99, with: summary)
        XCTAssertEqual(conv.messages.count, 1)
        XCTAssertEqual(conv.messages.first?.role, "system_summary")
    }

    func testCollapse_zeroIsNoOp() {
        let conv = CoachConversation()
        conv.append(CoachMessage(role: "user", text: "x"))
        conv.collapseEarlyMessages(
            upTo: 0,
            with: CoachMessage(role: "system_summary", text: "ignored")
        )
        XCTAssertEqual(conv.messages.count, 1)
        XCTAssertEqual(conv.messages.first?.text, "x")
    }

    // MARK: - Codable robustness

    func testToolCallsAndResultsRoundTrip() throws {
        let toolCall = PendingToolCall(
            id: "call-1",
            name: "moveMeal",
            inputJSON: Data(#"{"mealID":"abc","newTimeHHmm":"20:30"}"#.utf8)
        )
        let toolResult = ToolResult(
            toolUseID: "call-1",
            outputText: "Moved dinner 19:30 → 20:30",
            isError: false
        )
        let conv = CoachConversation(messages: [
            CoachMessage(role: "assistant", text: nil, toolCalls: [toolCall], model: "haiku"),
            CoachMessage(role: "user", toolResults: [toolResult]),
        ])

        // Re-decode via the accessor.
        let decoded = conv.messages
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.first?.toolCalls?.first?.name, "moveMeal")
        XCTAssertFalse(decoded.last?.toolResults?.first?.isError ?? true)
    }

    func testMessagesAccessor_corruptBlobReturnsEmptyArray() {
        let conv = CoachConversation()
        conv.messagesJSON = Data("not json".utf8)
        XCTAssertEqual(conv.messages.count, 0)
    }
}
