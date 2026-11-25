//
// LeaderboardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - LeaderboardView

// The weekly friends leaderboard: you and your friends, ranked by XP earned
// this ISO week (Monday to Sunday). The server owns the ranking; the numbers
// are the totals each friend's own phone pushed. Nobody is shown who is not a
// friend, and nothing is made up while the board loads or when it is empty.

struct LeaderboardView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(ArenaService.self)
    private var arena
    @Environment(\.modelContext)
    private var context
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State
    private var showInvite = false
    /// The podium blocks rise once, right after the board loads.
    @State
    private var risen = false

    /// Podium blocks, tallest in the middle.
    private static let pillarHeights: [Int: CGFloat] = [1: Tide.s10 * 3, 2: Tide.s10 * 2.5, 3: Tide.s10 * 2]

    var body: some View {
        TideScrollPage {
            switch arena.phase {
            case .idle,
                 .loading:
                ArenaListSkeleton(label: "Loading leaderboard")

            case let .failed(message):
                TideEmptyPanel(
                    systemImage: "wifi.exclamationmark", title: "Could not load the leaderboard",
                    message: message, actionTitle: "Try again"
                ) { Task { await arena.refresh() } }
                    .tideCard()

            case .ready:
                if arena.friends.isEmpty {
                    TideEmptyPanel(
                        systemImage: "trophy", title: "It's lonely at the top",
                        message: "Add a friend and your weekly XP lines up against theirs.",
                        actionTitle: "Invite a friend"
                    ) { showInvite = true }
                        .tideCard()
                } else if let board = arena.leaderboard {
                    content(board)
                }
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("arena.leaderboard")
        .refreshable { await arena.refresh() }
        .task {
            await arena.refresh()
            if reduceMotion {
                risen = true
            } else {
                try? await Task.sleep(for: .milliseconds(150))
                risen = true
            }
        }
        .sheet(isPresented: $showInvite) {
            FriendInviteSheet()
        }
    }

    @ViewBuilder
    private func content(_ board: ArenaLeaderboardDTO) -> some View {
        rankSummary(board)
        if showsPodium(board.rankings) {
            podium(board.rankings)
        }
        if !showsPodium(board.rankings) || board.rankings.count > 3 {
            rankedList(board.rankings)
        }
        if arena.isStale {
            Label("Showing the last numbers we got. Pull down to retry.", systemImage: "wifi.slash")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Your rank

    private func rankSummary(_ board: ArenaLeaderboardDTO) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s3))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            layout {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Your rank").tideLabel()
                    if let rank = board.myRank {
                        TideNumber("#\(rank)", size: Tide.numeralL, color: mood.accent)
                    }
                    if let gap = gapLine(board) {
                        Text(gap)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !stacked {
                    Spacer(minLength: Tide.s2)
                }
                VStack(alignment: stacked ? .leading : .trailing, spacing: Tide.s1) {
                    Text("This week").tideLabel()
                    TideNumber(board.myXP.formatted(), unit: "XP", size: Tide.numeralS, relativeTo: .headline)
                    Text("Resets Monday").font(Tide.caption).foregroundStyle(Tide.text3)
                }
            }
            if let rank = board.myRank {
                Button {
                    let start = ArenaCalendar.weekStart(containing: Date())
                    let summary = ArenaSync.syncLocal(context: context, services: services)
                    let week = ArenaWeekStats(summary: summary, weekStart: start)
                    ShareCard.present(.week(
                        xp: board.myXP, workouts: week.workouts, studyMinutes: week.studyMinutes,
                        rank: rank, friends: arena.friends.count, weekStart: start
                    ))
                } label: {
                    Label("Share my week", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("arena.shareWeek")
            }
        }
        .padding(.vertical, Tide.s2)
        .accessibilityElement(children: .contain)
    }

    /// How far to the next place, or that you lead.
    private func gapLine(_ board: ArenaLeaderboardDTO) -> String? {
        guard let rank = board.myRank else {
            return nil
        }
        if rank == 1 {
            return board.rankings.count > 1 ? "You lead the week" : nil
        }
        guard let ahead = board.rankings.first(where: { $0.rank == rank - 1 }) else {
            return nil
        }
        return "\((ahead.xp - board.myXP).formatted()) XP to pass \(ahead.user.displayName)"
    }

    // MARK: - Podium (Top 3)

    private func podium(_ rankings: [ArenaLeaderboardRankingDTO]) -> some View {
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

    private func podiumEntry(_ entry: ArenaLeaderboardRankingDTO) -> some View {
        let tint = podiumTint(entry.rank)
        let name = entry.isMe ? "You" : entry.user.displayName
        return VStack(spacing: Tide.s2) {
            if entry.rank == 1 {
                Image(systemName: "crown.fill").font(Tide.bodyStrong).foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            TideInitialAvatar(name: entry.user.displayName, size: Tide.avatarLarge, tint: tint)
            Text(name)
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
                .frame(
                    maxWidth: .infinity,
                    minHeight: (Self.pillarHeights[entry.rank] ?? Tide.s10) * (risen ? 1 : 0.25),
                    alignment: .top
                )
                .padding(.top, Tide.s3)
                .glassEffect(.regular.tint(tint.opacity(0.28)), in: .rect(cornerRadius: Tide.controlRadius))
                // First place rises last.
                .animation(Tide.settle.delay(Double(4 - min(entry.rank, 3)) * 0.1), value: risen)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(entry.rank), \(entry.isMe ? "you" : entry.user.displayName), \(entry.xp) XP")
    }

    // MARK: - Ranked List

    private func rankedList(_ rankings: [ArenaLeaderboardRankingDTO]) -> some View {
        let rows = Array(rankings.dropFirst(showsPodium(rankings) ? 3 : 0))
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    TideDivider()
                }
                ArenaRankRow(entry: entry, showsLevel: true)
            }
        }
        .tideCard(padding: Tide.s2)
    }

    /// Three columns of avatars and names do not fit at accessibility sizes; the
    /// list takes over and shows everyone, top three included.
    private func showsPodium(_ rankings: [ArenaLeaderboardRankingDTO]) -> Bool {
        rankings.count >= 3 && !typeSize.isAccessibilitySize
    }
}

// MARK: - ArenaRankRow

/// One person on the board: rank, avatar, name, XP. Used on the Arena home and
/// on the full leaderboard.
struct ArenaRankRow: View {
    let entry: ArenaLeaderboardRankingDTO
    var showsLevel = false

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        let name = entry.isMe ? "You" : entry.user.displayName
        layout {
            HStack(spacing: Tide.s3) {
                Group {
                    if entry.rank == 1 {
                        Image(systemName: "crown.fill").font(Tide.bodyStrong).foregroundStyle(TideTone.gold)
                    } else {
                        TideNumber("\(entry.rank)", size: Tide.numeralS, relativeTo: .headline, color: Tide.text2)
                    }
                }
                .frame(minWidth: Tide.s6)
                TideInitialAvatar(name: entry.user.displayName, size: Tide.avatar - Tide.s1)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(name)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(entry.isMe ? mood.accent : Tide.text)
                        .lineLimit(stacked ? 2 : 1)
                    if showsLevel {
                        Text("Level \(entry.user.level)").font(Tide.caption).foregroundStyle(Tide.text2)
                    }
                }
            }
            if !stacked {
                Spacer(minLength: Tide.s2)
            }
            TideNumber(
                entry.xp.formatted(), unit: "XP", size: Tide.numeralS, relativeTo: .headline,
                weight: .semibold, color: Tide.text
            )
        }
        .frame(minHeight: Tide.hit + (showsLevel ? Tide.s3 : 0))
        .padding(.horizontal, Tide.s2)
        .background(
            entry.isMe ? mood.accent.opacity(0.14) : .clear,
            in: .rect(cornerRadius: Tide.controlRadius)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rank \(entry.rank), \(entry.isMe ? "you" : entry.user.displayName), level \(entry.user.level), \(entry.xp) XP"
        )
    }
}
