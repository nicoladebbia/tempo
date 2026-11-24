//
// LeaderboardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - LeaderboardView

// Per MODULE_ARENA.md Section 7 — Full weekly leaderboard.
// Per WIREFRAMES.md Screen 37 — Period tabs, podium, ranked list.

struct LeaderboardView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var selectedPeriod: LeaderboardPeriod = .weekly
    @State
    private var rankings: [LeaderboardEntry] = []
    @State
    private var myRank: Int = 0
    @State
    private var isLoading = true

    /// Podium blocks, tallest in the middle.
    private static let pillarHeights: [Int: CGFloat] = [1: Tide.s10 * 3, 2: Tide.s10 * 2.5, 3: Tide.s10 * 2]

    var body: some View {
        TideScrollPage {
            TidePillPicker(
                options: LeaderboardPeriod.allCases,
                selection: $selectedPeriod,
                title: \.label,
                label: "Period"
            )

            if isLoading {
                ArenaListSkeleton(label: "Loading leaderboard")
            } else if rankings.isEmpty {
                TideEmptyPanel(
                    systemImage: "trophy",
                    title: "It's lonely at the top",
                    message: "Add friends to see who's grinding harder this week."
                )
                .tideCard()
            } else {
                if myRank > 0 {
                    rankSummary
                }
                if showsPodium {
                    podium
                }
                if !showsPodium || rankings.count != 3 { rankedList }
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadMockData() }
    }

    /// Three columns of avatars and names do not fit at accessibility sizes; the
    /// list takes over and shows everyone, top three included.
    private var showsPodium: Bool {
        rankings.count >= 3 && !typeSize.isAccessibilitySize
    }

    // MARK: - Your rank

    private var rankSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text("Your rank").tideLabel()
                TideNumber("#\(myRank)", size: Tide.numeralL, color: mood.accent)
            }
            Spacer(minLength: Tide.s2)
            if let me = rankings.first(where: \.isMe) {
                VStack(alignment: .trailing, spacing: Tide.s1) {
                    Text(selectedPeriod.label).tideLabel()
                    TideNumber(me.xp.formatted(), unit: "XP", size: Tide.numeralS, relativeTo: .headline)
                }
            }
        }
        .padding(.vertical, Tide.s2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Podium (Top 3)

    private var podium: some View {
        GlassEffectContainer(spacing: Tide.s3) {
            HStack(alignment: .bottom, spacing: Tide.s3) {
                // #2, #1, #3
                ForEach([1, 0, 2], id: \.self) { index in
                    if rankings.count > index {
                        podiumEntry(rankings[index])
                    }
                }
            }
        }
        .padding(.top, Tide.s2)
    }

    private func podiumTint(_ rank: Int) -> Color {
        switch rank {
        case 1: League.gold.tideTint
        case 2: League.silver.tideTint
        default: League.bronze.tideTint
        }
    }

    private func podiumEntry(_ entry: LeaderboardEntry) -> some View {
        let tint = podiumTint(entry.rank)
        return VStack(spacing: Tide.s2) {
            if entry.rank == 1 {
                Image(systemName: "crown.fill").font(Tide.bodyStrong).foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            TideInitialAvatar(name: entry.displayName, size: Tide.avatarLarge, tint: tint)
            Text(entry.isMe ? "You" : entry.displayName)
                .font(Tide.bodyStrong)
                .foregroundStyle(entry.isMe ? mood.accent : Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            TideNumber(
                entry.xp.formatted(),
                unit: "XP",
                size: Tide.numeralS,
                relativeTo: .headline,
                weight: .semibold,
                color: Tide.text2
            )
            TideNumber("\(entry.rank)", size: Tide.numeralM, relativeTo: .title2, color: tint)
                .frame(maxWidth: .infinity, minHeight: Self.pillarHeights[entry.rank] ?? Tide.s10, alignment: .top)
                .padding(.top, Tide.s3)
                .glassEffect(.regular.tint(tint.opacity(0.28)), in: .rect(cornerRadius: Tide.controlRadius))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(entry.rank), \(entry.isMe ? "you" : entry.displayName), \(entry.xp) XP")
    }

    // MARK: - Ranked List

    private var rankedList: some View {
        let rows = Array(rankings.dropFirst(showsPodium ? 3 : 0))
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    TideDivider()
                }
                row(entry)
            }
        }
        .tideCard(padding: Tide.s2)
    }

    private func row(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: Tide.s3) {
            TideNumber("\(entry.rank)", size: Tide.numeralS, relativeTo: .headline, color: Tide.text2)
                .frame(minWidth: Tide.s6)
            TideInitialAvatar(name: entry.displayName, size: Tide.avatar - Tide.s1)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(entry.isMe ? "You" : entry.displayName)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(entry.isMe ? mood.accent : Tide.text)
                    .lineLimit(1)
                Text("Level \(entry.level)").font(Tide.caption).foregroundStyle(Tide.text2)
            }
            Spacer(minLength: Tide.s2)
            TideNumber(
                entry.xp.formatted(),
                unit: "XP",
                size: Tide.numeralS,
                relativeTo: .headline,
                weight: .semibold
            )
        }
        .frame(minHeight: Tide.hit + Tide.s3)
        .padding(.horizontal, Tide.s3)
        .background(
            entry.isMe ? mood.accent.opacity(0.14) : .clear,
            in: .rect(cornerRadius: Tide.controlRadius)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(entry.rank), \(entry.isMe ? "you" : entry.displayName), level \(entry.level), \(entry.xp) XP")
    }

    // MARK: - Mock Data (until backend sync is wired)

    private func loadMockData() {
        // Placeholder data — will be replaced with real API calls
        rankings = [
            LeaderboardEntry(rank: 1, username: "marcus", displayName: "Marcus", xp: 2450, level: 8, isMe: false),
            LeaderboardEntry(rank: 2, username: "sofia", displayName: "Sofia", xp: 2280, level: 7, isMe: false),
            LeaderboardEntry(rank: 3, username: "you", displayName: "You", xp: 1890, level: 6, isMe: true),
            LeaderboardEntry(rank: 4, username: "jake", displayName: "Jake", xp: 1650, level: 5, isMe: false),
            LeaderboardEntry(rank: 5, username: "emma", displayName: "Emma", xp: 1420, level: 5, isMe: false),
        ]
        myRank = 3
        isLoading = false
    }
}

// MARK: - LeaderboardPeriod

enum LeaderboardPeriod: String, CaseIterable {
    case weekly
    case monthly
    case alltime

    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .alltime: "All-time"
        }
    }
}
