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
// Contains ArenaMainView with navigation to sub-views.

enum ArenaDestination: Hashable {
    case leaderboard
    case friends
    case challenges
    case achievements
    case activityFeed
}

// MARK: - ArenaTabView

struct ArenaTabView: View {
    @State
    private var path: [ArenaDestination] = []
    @Namespace
    private var zoom

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
                        case .achievements:
                            AchievementsView()
                        case .activityFeed:
                            ActivityFeedView()
                        }
                    }
                    .navigationTransition(.zoom(sourceID: destination, in: zoom))
                }
        }
    }
}
