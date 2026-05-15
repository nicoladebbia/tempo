//
// ArenaMainView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Arena Main View

// Per MODULE_ARENA.md Section 5 — XP summary, level badge, leaderboard preview, streak.
// Per WIREFRAMES.md Screen 36 — Arena Main layout.
// Enhanced with: weekly recap, activity feed, XP earning categories, level names.

struct ArenaMainView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Query(sort: \XPEvent.date, order: .reverse)
    private var xpEvents: [XPEvent]
    @Query
    private var achievements: [Achievement]
    @Query(filter: #Predicate<ChallengeLocal> { $0.isActive })
    private var activeChallenges: [ChallengeLocal]
    @Query(filter: #Predicate<Streak> { $0.typeRaw == "overall" })
    private var overallStreaks: [Streak]
    @Query
    private var allSettings: [UserSettings]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse)
    private var activityEvents: [ActivityEvent]

    @State
    private var viewModel: ArenaViewModel?
    @State
    private var showXPDetail = false

    private var settings: UserSettings? {
        allSettings.first
    }

    /// Show weekly recap on Mondays or if toggled.
    private var shouldShowWeeklyRecap: Bool {
        Calendar.current.component(.weekday, from: Date()) == 2 // Monday
    }

    var body: some View {
        ZStack {
            Group {
                switch viewModel?.loadState ?? .loading {
                case .loading:
                    VStack(spacing: TempoSpacing.md) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Color.tempoSignal)
                        Text("Loading Arena...")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case let .error(message):
                    VStack(spacing: TempoSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.tempoError)
                        Text("Something went wrong")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.tempoTextSecondary)
                            .multilineTextAlignment(.center)
                        Button {
                            refreshData()
                        } label: {
                            Text("Retry")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, TempoSpacing.xxl)
                                .padding(.vertical, TempoSpacing.md)
                                .background(Color.tempoSignal)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, TempoSpacing.xxl)

                case .loaded:
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: TempoSpacing.sm) {
                            heroCard
                            if shouldShowWeeklyRecap {
                                weeklyRecapCard
                            }
                            todayXPCard
                            activityPreviewCard
                            leaderboardPreviewCard
                            activeChallengesCard
                            recentAchievementsCard
                            challengeCTAButton
                        }
                        .padding(.horizontal, TempoSpacing.screenEdge)
                        .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
                    }
                }
            }

            // Floating XP gain animation
            if viewModel?.showXPGain == true {
                xpGainOverlay
            }

            // Streak freeze saved toast
            if viewModel?.showFreezeSaved == true {
                freezeSavedOverlay
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("ARENA")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshData() }
        .sheet(isPresented: $showXPDetail) {
            xpDetailSheet
        }
    }

    // MARK: - XP Gain Animation Overlay

    private var xpGainOverlay: some View {
        Text("+\(viewModel?.lastXPGainAmount ?? 0) XP")
            .font(.system(size: 28, weight: .black, design: .monospaced))
            .foregroundStyle(Color.tempoSignal)
            .shadow(color: Color.tempoSignal.opacity(0.5), radius: 8, x: 0, y: 0)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.6)) {
                        viewModel?.showXPGain = false
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }

    // MARK: - Streak Freeze Saved Overlay

    private var freezeSavedOverlay: some View {
        VStack(spacing: TempoSpacing.xs) {
            Image(systemName: "snowflake")
                .font(.system(size: 32))
                .foregroundStyle(Color.tempoInfo)
            Text("Freeze saved your streak!")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.tempoInk.opacity(0.2), radius: 12, x: 0, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    viewModel?.showFreezeSaved = false
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    // MARK: - Hero Card (Level + Streak + Next Level)

    // Enhanced: shows level name, progress to next named level.

    private var heroCard: some View {
        let currentLevel = viewModel?.level ?? 1
        let nextLevelName: String = {
            let nextLevel = currentLevel + 1
            if nextLevel <= LevelSystem.definitions.count {
                return LevelSystem.definition(for: nextLevel).name
            }
            return "Max"
        }()

        return VStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
                // Level badge
                ZStack {
                    Circle()
                        .fill(Color.tempoSignal.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text("\(currentLevel)")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoSignal)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(viewModel?.levelTitle.uppercased() ?? "RECRUIT")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Color.tempoTextSecondary)

                        // League badge
                        leagueBadge
                    }

                    // XP progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.tempoBorder)
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.tempoSignal)
                                .frame(width: geo.size.width * (viewModel?.xpProgress ?? 0), height: 5)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("\(viewModel?.xpForNextLevel ?? 100) XP to Lv.\(currentLevel + 1)")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.tempoTextTertiary)
                        Spacer()
                        Text(nextLevelName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.tempoSignal.opacity(0.7))
                    }
                }

                Spacer()

                // Daily XP goal ring
                CircularRingView(
                    progress: viewModel?.dailyXPProgress ?? 0,
                    color: .tempoSignal,
                    size: 44,
                    strokeWidth: 4,
                    label: "DAILY",
                    valueText: "\(viewModel?.todayXP ?? 0)"
                )
            }

            // Bottom row: streak + freezes
            HStack(spacing: TempoSpacing.md) {
                // Streak
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoAmber)
                    Text("\(viewModel?.streakDays ?? 0)")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoAmber)
                }

                // Streak freezes
                if (viewModel?.freezesAvailable ?? 0) > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.tempoInfo)
                        Text("\(viewModel?.freezesAvailable ?? 0)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.tempoInfo)
                    }
                }

                Spacer()

                // Total XP
                Text("\(viewModel?.totalXP ?? 0) XP total")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 1)
        )
    }

    // MARK: - League Badge

    private var leagueBadge: some View {
        let league = viewModel?.currentLeague ?? .bronze
        return HStack(spacing: 3) {
            Image(systemName: league.iconName)
                .font(.system(size: 10))
                .foregroundStyle(league.color)
            Text(league.displayName.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(league.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(league.color.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Weekly Recap Card

    // Shows total XP earned this week, achievements unlocked, rank change.
    // Displayed on Mondays (or can be toggled).

    private var weeklyRecapCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tempoAmber)
                Text("WEEKLY RECAP")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            HStack(spacing: TempoSpacing.lg) {
                // XP earned
                VStack(spacing: 4) {
                    Text("+\(viewModel?.weeklyXPEarned ?? 0)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoSignal)
                    Text("XP Earned")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                Divider()
                    .frame(height: 36)
                    .background(Color.tempoDivider)

                // Achievements
                VStack(spacing: 4) {
                    Text("\(viewModel?.weeklyAchievementsUnlocked ?? 0)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoViolet)
                    Text("Unlocked")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                Divider()
                    .frame(height: 36)
                    .background(Color.tempoDivider)

                // Rank change
                let rankChange = viewModel?.weeklyRankChange ?? 0
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        if rankChange > 0 {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.tempoSuccess)
                                .accessibilityHidden(true)
                        } else if rankChange < 0 {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.tempoError)
                                .accessibilityHidden(true)
                        }
                        Text("\(abs(rankChange))")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(rankChange >= 0 ? Color.tempoSuccess : Color.tempoError)
                    }
                    Text("Rank")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rankChange > 0
                    ? "Rank up \(abs(rankChange))"
                    : rankChange < 0
                        ? "Rank down \(abs(rankChange))"
                        : "Rank unchanged")

                Divider()
                    .frame(height: 36)
                    .background(Color.tempoDivider)

                // Streak
                VStack(spacing: 4) {
                    Text("\(viewModel?.streakDays ?? 0)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoAmber)
                    Text("Streak")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(TempoSpacing.cardPadding)
        .background(
            LinearGradient(
                colors: [Color.tempoAmber.opacity(0.08), Color.tempoSurfaceCard],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoAmber.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Today's XP Card

    private var todayXPCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack {
                Text("TODAY'S XP")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                if viewModel?.streakMultiplier ?? 1.0 > 1.0 {
                    Text(String(format: "%.0fx", viewModel?.streakMultiplier ?? 1.0))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoAmber)
                }
            }

            Text("+\(viewModel?.todayXP ?? 0)")
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.tempoSignal)
                .contentTransition(.numericText())

            // Breakdown rows
            if let breakdown = viewModel?.xpBreakdown, !breakdown.isEmpty {
                ForEach(breakdown) { row in
                    HStack {
                        Text(row.emoji)
                            .font(.system(size: 16))
                        Text(row.label)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.tempoTextSecondary)
                        Spacer()
                        Text(row.source == .penalty ? "\(row.xp) XP" : "+\(row.xp) XP")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(row.source == .penalty ? Color.tempoError : Color.tempoSignal)
                    }
                    .frame(height: 28)
                }
            } else {
                Text("Complete activities to earn XP!")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            HStack {
                Spacer()
                Button {
                    showXPDetail = true
                } label: {
                    Text("See Details >")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .tempoCard()
    }

    // MARK: - Activity Preview Card

    private var activityPreviewCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("RECENT ACTIVITY")
                }
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                NavigationLink(value: ArenaDestination.activityFeed) {
                    Text("See All >")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tempoSignal)
                }
            }

            if activityEvents.isEmpty {
                Text("Your activity will appear here.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, TempoSpacing.sm)
            } else {
                ForEach(activityEvents.prefix(3), id: \.id) { event in
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: event.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.tempoSignal)
                            .frame(width: 24)

                        Text(event.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.tempoTextPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(event.timeAgo)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .frame(height: 28)
                }
            }
        }
        .tempoCard()
    }

    // MARK: - Leaderboard Preview

    private var leaderboardPreviewCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("WEEKLY LEADERBOARD")
                }
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                NavigationLink(value: ArenaDestination.leaderboard) {
                    Text("See All >")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tempoSignal)
                }
            }

            if let entries = viewModel?.leaderboardPreview, !entries.isEmpty {
                ForEach(entries) { entry in
                    leaderboardRow(entry)
                }
            } else {
                VStack(spacing: TempoSpacing.sm) {
                    Text("Add friends to compete!")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoTextTertiary)
                    NavigationLink(value: ArenaDestination.friends) {
                        Text("Invite Friends")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.tempoSignal)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TempoSpacing.md)
            }
        }
        .tempoCard()
    }

    private func leaderboardRow(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            if entry.rank == 1 {
                Text("👑")
                    .font(.system(size: 16))
                    .frame(width: 28)
            } else {
                Text("#\(entry.rank)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(width: 28)
            }

            Circle()
                .fill(Color.tempoSignal.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(entry.displayName.prefix(1)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.tempoSignal)
                )

            Text(entry.isMe ? "You" : entry.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(entry.isMe ? Color.tempoSignal : Color.tempoTextPrimary)

            Spacer()

            Text("\(entry.xp) XP")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(height: 36)
        .padding(.horizontal, TempoSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(entry.isMe ? Color.tempoSignal.opacity(0.08) : Color.clear)
        )
    }

    // MARK: - Active Challenges Card

    private var activeChallengesCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "figure.fencing")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("ACTIVE CHALLENGES")
                }
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                NavigationLink(value: ArenaDestination.challenges) {
                    Text("See All >")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tempoSignal)
                }
            }

            if activeChallenges.isEmpty {
                Text("No active challenges. Start one!")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, TempoSpacing.sm)
            } else {
                ForEach(activeChallenges.prefix(2), id: \.id) { challenge in
                    VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                        Text(challenge.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.tempoTextPrimary)
                        HStack {
                            Text("\(challenge.daysRemaining) days left")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.tempoTextTertiary)
                            Spacer()
                            Text(String(format: "%.0f", challenge.myScore))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.tempoSignal)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.tempoBorder)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.tempoSignal)
                                    .frame(width: geo.size.width * challenge.timelineProgress, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }

                    if challenge.id != activeChallenges.prefix(2).last?.id {
                        Divider()
                            .background(Color.tempoDivider)
                    }
                }

                if activeChallenges.count > 2 {
                    Text("+\(activeChallenges.count - 2) more")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
        .tempoCard()
    }

    // MARK: - Recent Achievements Card

    private var recentAchievementsCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("RECENT ACHIEVEMENTS")
                }
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                NavigationLink(value: ArenaDestination.achievements) {
                    Text("View All >")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.tempoSignal)
                }
            }

            if let recent = viewModel?.recentAchievements, !recent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TempoSpacing.md) {
                        ForEach(recent, id: \.id) { achievement in
                            achievementBadge(achievement)
                        }
                    }
                }
            } else {
                Text("Complete tasks to unlock achievements!")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, TempoSpacing.sm)
            }
        }
        .tempoCard()
    }

    private func achievementBadge(_ achievement: Achievement) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.tempoSuccess.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "star.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.tempoSuccess)
            }
            Text(achievement.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)
                .frame(width: 52)
        }
    }

    // MARK: - Challenge a Friend CTA

    private var challengeCTAButton: some View {
        NavigationLink(value: ArenaDestination.challenges) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18))
                Text("Challenge a Friend")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                LinearGradient(
                    colors: [Color.tempoSignal, Color.tempoViolet],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - XP Detail Sheet (Enhanced with all earning categories)

    private var xpDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    Text("TODAY'S XP BREAKDOWN")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .padding(.top, TempoSpacing.lg)

                    // Earned section
                    if let breakdown = viewModel?.xpBreakdown {
                        Text("EARNED")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.tempoSuccess)

                        ForEach(breakdown.filter { $0.source != .penalty }) { row in
                            HStack {
                                Text(row.emoji)
                                Text(row.label)
                                    .foregroundStyle(Color.tempoTextSecondary)
                                Spacer()
                                Text("+\(row.xp) XP")
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.tempoSignal)
                            }
                            .font(.system(size: 14))
                        }

                        // Penalties
                        let penalties = breakdown.filter { $0.source == .penalty }
                        if !penalties.isEmpty {
                            Divider().background(Color.tempoDivider)

                            Text("PENALTIES")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.tempoError)

                            ForEach(penalties) { row in
                                HStack {
                                    Text(row.emoji)
                                    Text(row.label)
                                        .foregroundStyle(Color.tempoTextSecondary)
                                    Spacer()
                                    Text("\(row.xp) XP")
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.tempoError)
                                }
                                .font(.system(size: 14))
                            }
                        }

                        Divider().background(Color.tempoDivider)

                        // Total
                        HStack {
                            Text("TOTAL EARNED")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("+\(viewModel?.todayXP ?? 0) XP")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.tempoTextPrimary)
                        }

                        // Multiplier
                        if (viewModel?.streakMultiplier ?? 1.0) > 1.0 {
                            HStack {
                                Text("Streak multiplier")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.tempoTextSecondary)
                                Spacer()
                                Text(String(format: "%.2fx", viewModel?.streakMultiplier ?? 1.0))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.tempoAmber)
                            }
                            .padding(TempoSpacing.sm)
                            .background(Color.tempoSignal.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // All earning categories reference
                    Divider().background(Color.tempoDivider)
                        .padding(.top, TempoSpacing.sm)

                    Text("HOW TO EARN XP")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.tempoTextSecondary)

                    ForEach(XPEngine.xpEarningCategories) { category in
                        HStack(alignment: .top, spacing: TempoSpacing.sm) {
                            Text(category.emoji)
                                .font(.system(size: 16))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.tempoTextPrimary)
                                Text(category.description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                            Spacer()
                            Text(category.xpRange)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.tempoSignal)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Data Refresh

    private func refreshData() {
        if viewModel == nil {
            viewModel = ArenaViewModel(xpEngine: services.xpEngine)
        }

        viewModel?.load(
            xpEvents: xpEvents,
            achievements: achievements,
            challenges: activeChallenges,
            userTotalXP: xpEvents.reduce(0) { $0 + $1.amount },
            userStreakDays: overallStreaks.first?.currentCount ?? 0,
            settings: settings,
            streak: overallStreaks.first,
            activityEvents: activityEvents
        )
    }
}
