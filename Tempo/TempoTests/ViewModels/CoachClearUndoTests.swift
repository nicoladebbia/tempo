//
// CoachClearUndoTests.swift
// TempoTests
//
// "Chat cleared" with Undo: the chat is gone from the screen at once, the old
// one comes back whole on Undo, and nothing that cannot be taken back (the
// preference extractor reading the transcript) runs until the toast is over.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachClearUndoTests: XCTestCase {
    private final class ScriptedAI: CoachChatAIClient, @unchecked Sendable {
        func sendChat(request _: CoachChatRequest) async throws -> CoachChatResponse {
            throw NSError(domain: "test", code: 503)
        }
    }

    private final class NoopSummarizer: ConversationSummarizerAIClient, @unchecked Sendable {
        func summarize(request _: ConversationSummarizationRequest) async throws -> String {
            "summary"
        }
    }

    private final class NoopDispatcher: CoachToolDispatcher, @unchecked Sendable {
        func dispatch(
            toolName _: String, inputJSON _: Data, context _: ModelContext
        ) async throws -> CoachToolDispatchResult {
            CoachToolDispatchResult(output: ToolOutput(summary: "ok"))
        }
    }

    /// Counts how many times the extractor was asked to read a chat.
    private final class CountingExtractor: PreferenceExtractionAIClient, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var onCall: (@Sendable () -> Void)?

        var calls: Int {
            lock.withLock { count }
        }

        func extractPreferences(prompt _: String) async throws -> [PreferenceCandidate] {
            lock.withLock { count += 1 }
            onCall?()
            return []
        }
    }

    private var container: ModelContainer!
    private var context: ModelContext!
    private var extractor: CountingExtractor!
    private var vm: CoachViewModel!

    override func setUp() async throws {
        let schema = Schema([
            CoachConversation.self,
            LearnedPreference.self,
            LearnedOutcome.self,
            PendingOutcome.self,
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        extractor = CountingExtractor()
        vm = CoachViewModel(
            service: CoachService(
                aiClient: ScriptedAI(), summarizerClient: NoopSummarizer(), toolDispatcher: NoopDispatcher()
            ),
            extractorClient: extractor
        )
    }

    override func tearDown() async throws {
        vm = nil
        extractor = nil
        context = nil
        container = nil
    }

    /// An active chat with two turns in it.
    private func startChat() throws -> CoachConversation {
        let chat = CoachConversation(messages: [
            CoachMessage(role: "user", text: "I never eat before 11am"),
            CoachMessage(role: "assistant", text: "Got it."),
        ])
        context.insert(chat)
        try context.save()
        vm.loadOrStartConversation(context: context)
        XCTAssertEqual(vm.activeConversation?.id, chat.id)
        return chat
    }

    private func conversations() throws -> [CoachConversation] {
        try context.fetch(FetchDescriptor<CoachConversation>())
    }

    /// Lets a fire-and-forget Task run.
    private func settle() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }

    func testClearEmptiesTheScreenAtOnceAndStartsAFreshChat() throws {
        let old = try startChat()
        XCTAssertTrue(vm.endConversationWithUndo(context: context))
        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertNotEqual(vm.activeConversation?.id, old.id)
        XCTAssertFalse(old.isActive)
        XCTAssertEqual(try conversations().filter(\.isActive).count, 1)
    }

    func testClearDoesNotReadTheTranscriptUntilItIsFinal() async throws {
        _ = try startChat()
        vm.endConversationWithUndo(context: context)
        await settle()
        XCTAssertEqual(extractor.calls, 0, "the transcript goes to the server only when Undo is over")
    }

    func testUndoBringsTheSameChatBackWholeAndDropsTheEmptyOne() async throws {
        let old = try startChat()
        let before = old.messages
        vm.endConversationWithUndo(context: context)
        XCTAssertTrue(vm.undoEnd())
        XCTAssertEqual(vm.activeConversation?.id, old.id)
        XCTAssertEqual(vm.messages, before)
        XCTAssertTrue(old.isActive)
        let stored = try conversations()
        XCTAssertEqual(stored.count, 1, "the empty replacement is gone")
        await settle()
        XCTAssertEqual(extractor.calls, 0)
        XCTAssertNil(vm.pendingEnd)
    }

    func testFinishingTheToastReadsTheClearedTranscriptOnce() async throws {
        _ = try startChat()
        let done = expectation(description: "extractor ran")
        extractor.onCall = { done.fulfill() }
        vm.endConversationWithUndo(context: context)
        vm.commitPendingEnd()
        vm.commitPendingEnd()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(extractor.calls, 1)
        XCTAssertFalse(vm.undoEnd(), "too late once it is final")
    }

    func testWritingInTheFreshChatMakesTheClearFinal() async throws {
        _ = try startChat()
        let done = expectation(description: "extractor ran")
        extractor.onCall = { done.fulfill() }
        vm.endConversationWithUndo(context: context)
        await vm.sendMessage("hello again", systemPrompt: "sys", context: context)
        await fulfillment(of: [done], timeout: 2)
        XCTAssertNil(vm.pendingEnd)
        XCTAssertFalse(vm.undoEnd())
    }

    func testClearingAnEmptyChatDoesNothingAndAsksTheScreenToClose() throws {
        vm.loadOrStartConversation(context: context)
        let id = vm.activeConversation?.id
        XCTAssertFalse(vm.endConversationWithUndo(context: context))
        XCTAssertEqual(vm.activeConversation?.id, id)
        XCTAssertNil(vm.pendingEnd)
        XCTAssertEqual(try conversations().count, 1)
    }

    func testAnotherClearMakesTheFirstOneFinal() async throws {
        _ = try startChat()
        let done = expectation(description: "extractor ran")
        extractor.onCall = { done.fulfill() }
        vm.endConversationWithUndo(context: context)
        // The fresh chat is empty, so the second clear has nothing to take.
        XCTAssertFalse(vm.endConversationWithUndo(context: context))
        await fulfillment(of: [done], timeout: 2)
        XCTAssertNil(vm.pendingEnd)
    }
}
