//
// ArenaSync.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import Foundation
import SwiftData

// MARK: - ArenaSync

// Keeps the Arena true: write the XP the user's records are worth
// (ArenaXPLedger), then tell the server, so friends' boards move. The Arena runs
// both when it opens; the app root runs them when the app comes to the front
// (ArenaConnectModifier), so a friend who trained but never opened the Arena
// still shows up on your board.

@MainActor
enum ArenaSync {
    /// When the root last ran it, to avoid doing the work on every quick app switch.
    private static var lastRootRun: Date?
    private static let rootInterval: TimeInterval = 10 * 60

    /// Step one, on the phone only: bring XP, achievements and the profile in line.
    static func syncLocal(context: ModelContext, services: ServiceContainer, now: Date = Date()) -> ArenaXPLedger.Summary {
        ArenaXPLedger.sync(in: context, engine: services.xpEngine, now: now)
    }

    /// Step two: tell the server (only when signed in).
    static func push(
        _ summary: ArenaXPLedger.Summary, context: ModelContext, services: ServiceContainer, force: Bool = false
    ) async {
        guard case let .authenticated(userID) = services.authService.authState else {
            return
        }
        let name = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.displayName
        await ArenaService.push(
            summary,
            userID: userID,
            displayName: name,
            streakDays: ArenaXPLedger.streakDays(in: context),
            apiClient: services.apiClient,
            force: force
        )
    }

    /// Both steps.
    @discardableResult
    static func run(
        context: ModelContext, services: ServiceContainer, force: Bool = false, now: Date = Date()
    ) async -> ArenaXPLedger.Summary {
        let summary = syncLocal(context: context, services: services, now: now)
        await push(summary, context: context, services: services, force: force)
        return summary
    }

    /// The app-root version: at most once every ten minutes.
    static func runFromRoot(context: ModelContext, services: ServiceContainer, now: Date = Date()) async {
        if let last = lastRootRun, now.timeIntervalSince(last) < rootInterval {
            return
        }
        lastRootRun = now
        await run(context: context, services: services, now: now)
    }
}
