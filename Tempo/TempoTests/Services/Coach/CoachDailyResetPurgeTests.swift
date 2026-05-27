//
// CoachDailyResetPurgeTests.swift
// Tempo
//
// Coach v2.1 Phase 7c — covers the 30-day conversation purge wired
// into DailyResetCoordinator. Pure data + date math; verifies the
// keep / delete / star-immune rules.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachDailyResetPurgeTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([CoachConversation.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeConversation(
        lastMessageAt: Date,
        isStarred: Bool = false,
        in context: ModelContext
    ) -> CoachConversation {
        let conv = CoachConversation(
            startedAt: lastMessageAt,
            lastMessageAt: lastMessageAt,
            isStarred: isStarred
        )
        context.insert(conv)
        return conv
    }

    func testPurge_deletesUnstarredOlderThan30Days() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        let calendar = Calendar.current

        let old = makeConversation(
            lastMessageAt: calendar.date(byAdding: .day, value: -45, to: today)!,
            in: context
        )
        let recent = makeConversation(
            lastMessageAt: calendar.date(byAdding: .day, value: -5, to: today)!,
            in: context
        )
        try context.save()

        let purged = DailyResetCoordinator.purgeStaleCoachConversations(
            in: context,
            today: today
        )
        try context.save()

        XCTAssertEqual(purged, 1)
        let remaining = try context.fetch(FetchDescriptor<CoachConversation>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, recent.id)
        _ = old // captured to keep insert from being optimized away
    }

    func testPurge_keepsStarredEvenWhenOld() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        let calendar = Calendar.current
        let staredOld = makeConversation(
            lastMessageAt: calendar.date(byAdding: .day, value: -90, to: today)!,
            isStarred: true,
            in: context
        )
        try context.save()

        let purged = DailyResetCoordinator.purgeStaleCoachConversations(
            in: context,
            today: today
        )
        try context.save()

        XCTAssertEqual(purged, 0)
        let remaining = try context.fetch(FetchDescriptor<CoachConversation>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, staredOld.id)
    }

    func testPurge_boundaryDayKept() throws {
        // Exactly 30 days old — lastMessageAt == cutoff, which is NOT
        // strictly less than. Should be kept.
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        let calendar = Calendar.current
        _ = makeConversation(
            lastMessageAt: calendar.date(byAdding: .day, value: -30, to: today)!,
            in: context
        )
        try context.save()
        let purged = DailyResetCoordinator.purgeStaleCoachConversations(
            in: context,
            today: today
        )
        XCTAssertEqual(purged, 0, "exactly maxAgeDays-old conversations stay")
    }

    func testPurge_emptyContextReturnsZero() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let purged = DailyResetCoordinator.purgeStaleCoachConversations(
            in: context,
            today: Date()
        )
        XCTAssertEqual(purged, 0)
    }

    func testPurge_customMaxAge() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let today = Date()
        let calendar = Calendar.current
        _ = makeConversation(
            lastMessageAt: calendar.date(byAdding: .day, value: -10, to: today)!,
            in: context
        )
        try context.save()
        // 7-day cap → the 10-day-old conversation is stale.
        let purged = DailyResetCoordinator.purgeStaleCoachConversations(
            in: context,
            today: today,
            maxAgeDays: 7
        )
        XCTAssertEqual(purged, 1)
    }
}
