//
// ArenaTabView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - ArenaDestination

// Per MODULE_ARENA.md Section 5.1 — 5th tab, trophy.fill icon.
// The home carries the leaderboard; four pages open from it.

enum ArenaDestination: Hashable {
    case leaderboard
    case friends
    case challenges
    /// Achievements and recent activity, one page.
    case earned
}

// MARK: - ArenaTabView

struct ArenaTabView: View {
    @Environment(ServiceContainer.self)
    private var services

    var body: some View {
        ArenaTabContent(apiClient: services.apiClient)
    }
}

// MARK: - ArenaTabContent

/// Owns the one `ArenaService` every Arena page reads.
private struct ArenaTabContent: View {
    @State
    private var path: [ArenaDestination] = []
    @State
    private var arena: ArenaService
    @Namespace
    private var zoom

    init(apiClient: APIClient) {
        _arena = State(initialValue: ArenaService(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ArenaMainView(zoom: zoom)
                // The home's shaders rest while a page covers it.
                .tideCovered(!path.isEmpty)
                .navigationDestination(for: ArenaDestination.self) { destination in
                    Group {
                        switch destination {
                        case .leaderboard:
                            LeaderboardView()
                        case .friends:
                            FriendSystemView()
                        case .challenges:
                            ChallengesView()
                        case .earned:
                            ArenaEarnedView()
                        }
                    }
                    .navigationTransition(.zoom(sourceID: destination, in: zoom))
                }
        }
        .environment(arena)
        // A friend was added from an invite link: show them straight away.
        .onReceive(NotificationCenter.default.publisher(for: .arenaFriendsChanged)) { _ in
            Task { await arena.refresh() }
        }
    }
}
