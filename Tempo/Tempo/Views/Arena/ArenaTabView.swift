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
    var body: some View {
        NavigationStack {
            ArenaMainView()
                .navigationDestination(for: ArenaDestination.self) { destination in
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
        }
    }
}
