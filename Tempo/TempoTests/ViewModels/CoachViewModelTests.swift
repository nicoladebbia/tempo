//
// CoachViewModelTests.swift
// Tempo
//
// Coach v2.1 Phase 7a — covers the view-model lifecycle: loading a
// fresh vs existing conversation, mirroring messages, error mapping,
// undo refresh, conversation end, and retrying a failed turn.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachViewModelTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CoachConversation.self,
            LearnedPreference.self,
            LearnedOutcome.self,
            PendingOutcome.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // Reuse the scripted stubs from CoachServiceTests-style fixtures.
    final class ScriptedAIClient: CoachChatAIClient, @unchecked Sendable {
        var scripted: [CoachChatResponse] = []
        func sendChat(request _: CoachChatRequest) async throws -> CoachChatResponse {
            guard !scripted.isEmpty else { throw NSError(domain: "test", code: 503) }
            return scripted.removeFirst()
        }
    }

    final class NoopSummarizer: ConversationSummarizerAIClient, @unchecked Sendable {
        func summarize(request _: ConversationSummarizationRequest) async throws -> String {
            "summary"
        }
    }

    final class NoopDispatcher: CoachToolDispatcher, @unchecked Sendable {
        func dispatch(
            toolName _: String, inputJSON _: Data, context _: ModelContext
        ) async throws -> CoachToolDispatchResult {
            CoachToolDispatchResult(output: ToolOutput(summary: "ok"))
        }
    }

    private func makeService() -> CoachService {
        CoachService(
            aiClient: ScriptedAIClient(),
            summarizerClient: NoopSummarizer(),
            toolDispatcher: NoopDispatcher()
        )
    }

    // MARK: - loadOrStartConversation

    func testLoadOrStart_createsFreshConversationWhenNoneActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = CoachViewModel(service: makeService())
        XCTAssertNil(vm.activeConversation)
        vm.loadOrStartConversation(context: context)
        XCTAssertNotNil(vm.activeConversation)
        let stored = try context.fetch(FetchDescriptor<CoachConversation>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(stored.first?.isActive ?? false)
    }

    func testLoadOrStart_reusesExistingActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = CoachConversation()
        context.insert(existing)
        try context.save()
        let originalID = existing.id

        let vm = CoachViewModel(service: makeService())
        vm.loadOrStartConversation(context: context)
        XCTAssertEqual(vm.activeConversation?.id, originalID)
        let stored = try context.fetch(FetchDescriptor<CoachConversation>())
        XCTAssertEqual(stored.count, 1)
    }

    func testLoadOrStart_populatesPendingReviewQueue() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let flagged = LearnedPreference(
            text: "lifts Tuesdays",
            subject: "training.match_days",
            source: .observed,
            confidence: 0.85,
            needsReview: true
        )
        context.insert(flagged)
        try context.save()

        let vm = CoachViewModel(service: makeService())
        vm.loadOrStartConversation(context: context)
        XCTAssertEqual(vm.pendingReviewPreferenceIDs.count, 1)
        XCTAssertEqual(vm.pendingReviewPreferenceIDs.first, flagged.id)
    }

    // MARK: - sendMessage

    func testSendMessage_mirrorsMessagesAfterSuccess() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ai = ScriptedAIClient()
        ai.scripted = [
            CoachChatResponse(content: [.text("Got it.")], stopReason: .endTurn),
        ]
        let service = CoachService(
            aiClient: ai,
            summarizerClient: NoopSummarizer(),
            toolDispatcher: NoopDispatcher()
        )
        let vm = CoachViewModel(service: service)
        vm.loadOrStartConversation(context: context)

        await vm.sendMessage("soccer at 7pm", systemPrompt: "sys", context: context)
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages.first?.role, "user")
        XCTAssertEqual(vm.messages.last?.text, "Got it.")
        XCTAssertFalse(vm.isThinking)
        XCTAssertNil(vm.pendingError)
    }

    func testSendMessage_capReachedSetsPendingError() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ai = ScriptedAIClient()
        // 8 tool_use responses → cap fires.
        for i in 0..<8 {
            ai.scripted.append(CoachChatResponse(
                content: [.toolUse(id: "t-\(i)", name: "moveMeal", input: Data())],
                stopReason: .toolUse
            ))
        }
        let service = CoachService(
            aiClient: ai,
            summarizerClient: NoopSummarizer(),
            toolDispatcher: NoopDispatcher()
        )
        let vm = CoachViewModel(service: service)
        vm.loadOrStartConversation(context: context)
        await vm.sendMessage("x", systemPrompt: "sys", context: context)
        XCTAssertNotNil(vm.pendingError)
        XCTAssertTrue(vm.pendingError?.contains("limit") ?? false)
    }

    func testSendMessage_503ErrorSetsCriticalBudgetState() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // AI client throws 503-like error → budgetState should flip critical.
        final class ThrowingAI: CoachChatAIClient, @unchecked Sendable {
            func sendChat(request _: CoachChatRequest) async throws -> CoachChatResponse {
                throw NSError(
                    domain: "test", code: 503,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP 503 Service Unavailable"]
                )
            }
        }
        let service = CoachService(
            aiClient: ThrowingAI(),
            summarizerClient: NoopSummarizer(),
            toolDispatcher: NoopDispatcher()
        )
        let vm = CoachViewModel(service: service)
        vm.loadOrStartConversation(context: context)
        await vm.sendMessage("x", systemPrompt: "sys", context: context)
        XCTAssertEqual(vm.budgetState, .critical)
        XCTAssertTrue(vm.pendingError?.contains("limit") ?? false)
    }

    func testSendMessage_emptyInputDoesNotErrorButNoOps() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = CoachViewModel(service: makeService())
        vm.loadOrStartConversation(context: context)
        await vm.sendMessage("   ", systemPrompt: "sys", context: context)
        XCTAssertNil(vm.pendingError)
        XCTAssertTrue(vm.messages.isEmpty)
    }

    // MARK: - endConversation

    func testEndConversation_marksInactiveAndClearsState() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = CoachViewModel(service: makeService())
        vm.loadOrStartConversation(context: context)
        let convID = try XCTUnwrap(vm.activeConversation?.id)
        vm.endConversation(context: context)
        XCTAssertNil(vm.activeConversation)
        XCTAssertTrue(vm.messages.isEmpty)
        // Persisted row still exists but isActive=false.
        let descriptor = FetchDescriptor<CoachConversation>(
            predicate: #Predicate<CoachConversation> { $0.id == convID }
        )
        let stored = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertFalse(stored.isActive)
    }

    // MARK: - Retry

    /// Fails the first `failures` calls, then answers.
    final class FlakyAI: CoachChatAIClient, @unchecked Sendable {
        var failures: Int
        private(set) var requests: [CoachChatRequest] = []
        init(failures: Int) { self.failures = failures }
        func sendChat(request: CoachChatRequest) async throws -> CoachChatResponse {
            requests.append(request)
            if failures > 0 {
                failures -= 1
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "offline"])
            }
            return CoachChatResponse(content: [.text("Back online.")], stopReason: .endTurn)
        }
    }

    private func makeFlakyViewModel(failures: Int) throws -> (CoachViewModel, FlakyAI, ModelContext) {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ai = FlakyAI(failures: failures)
        let service = CoachService(
            aiClient: ai,
            summarizerClient: NoopSummarizer(),
            toolDispatcher: NoopDispatcher()
        )
        let vm = CoachViewModel(service: service)
        vm.loadOrStartConversation(context: context)
        return (vm, ai, context)
    }

    func testFailedSend_keepsTheUserMessageAndOffersRetry() async throws {
        let (vm, _, context) = try makeFlakyViewModel(failures: 1)
        await vm.sendMessage("soccer at 7pm", systemPrompt: "sys", context: context)

        XCTAssertNotNil(vm.pendingError)
        XCTAssertEqual(vm.messages.map(\.role), ["user"])
        XCTAssertTrue(vm.canRetry)
    }

    func testRetry_answersTheSameMessageWithoutAddingItTwice() async throws {
        let (vm, ai, context) = try makeFlakyViewModel(failures: 1)
        await vm.sendMessage("soccer at 7pm", systemPrompt: "sys", context: context)
        await vm.retryLast(systemPrompt: "sys", context: context)

        XCTAssertNil(vm.pendingError)
        XCTAssertFalse(vm.canRetry)
        XCTAssertEqual(vm.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(vm.messages.first?.text, "soccer at 7pm")
        XCTAssertEqual(vm.messages.last?.text, "Back online.")
        // The second request carried the one user message, not two.
        XCTAssertEqual(ai.requests.count, 2)
        XCTAssertEqual(ai.requests.last?.history.filter { $0.role == "user" }.count, 1)
    }

    func testRetry_failingAgainKeepsOneMessageAndStillOffersRetry() async throws {
        let (vm, _, context) = try makeFlakyViewModel(failures: 2)
        await vm.sendMessage("soccer at 7pm", systemPrompt: "sys", context: context)
        await vm.retryLast(systemPrompt: "sys", context: context)

        XCTAssertNotNil(vm.pendingError)
        XCTAssertEqual(vm.messages.map(\.role), ["user"])
        XCTAssertTrue(vm.canRetry)
    }

    func testRetry_withNothingToRetryDoesNothing() async throws {
        let (vm, ai, context) = try makeFlakyViewModel(failures: 0)
        XCTAssertFalse(vm.canRetry)
        await vm.retryLast(systemPrompt: "sys", context: context)
        XCTAssertTrue(ai.requests.isEmpty)
        XCTAssertTrue(vm.messages.isEmpty)
    }

    func testLastUnansweredUserText_isNilWhenCoachHasAnswered() {
        let answered = [CoachMessage(role: "user", text: "hi"), CoachMessage(role: "assistant", text: "hello")]
        XCTAssertNil(CoachViewModel.lastUnansweredUserText(in: answered))
        let unanswered = [CoachMessage(role: "assistant", text: "hello"), CoachMessage(role: "user", text: "hi")]
        XCTAssertEqual(CoachViewModel.lastUnansweredUserText(in: unanswered), "hi")
    }

    // MARK: - Budget state

    func testSetBudgetState_canBeClearedExternally() {
        let vm = CoachViewModel(service: makeService())
        vm.setBudgetState(.caution)
        XCTAssertEqual(vm.budgetState, .caution)
        vm.setBudgetState(nil)
        XCTAssertNil(vm.budgetState)
    }
}
