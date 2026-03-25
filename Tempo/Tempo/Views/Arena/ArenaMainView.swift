import SwiftUI
import SwiftData

// MARK: - Arena Main View
// Per MODULE_ARENA.md Section 5 — XP summary, level badge, leaderboard preview, streak.
// Per WIREFRAMES.md Screen 36 — Arena Main layout.

struct ArenaMainView: View {

    @Environment(ServiceContainer.self) private var services
    @Query(sort: \XPEvent.date, order: .reverse) private var xpEvents: [XPEvent]
    @Query private var achievements: [Achievement]
    @Query(filter: #Predicate<ChallengeLocal> { $0.isActive }) private var activeChallenges: [ChallengeLocal]
    @Query private var allSettings: [UserSettings]

    @State private var viewModel: ArenaViewModel?
    @State private var showXPDetail = false
    @State private var showLeaderboard = false
    @State private var showFriends = false
    @State private var showChallenges = false
    @State private var showAchievements = false

    private var settings: UserSettings? { allSettings.first }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.lg) {
                heroCard
                todayXPCard
                leaderboardPreviewCard
                activeChallengesCard
                recentAchievementsCard
                challengeCTAButton
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.xxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("ARENA")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { refreshData() }
        .sheet(isPresented: $showXPDetail) {
            xpDetailSheet
        }
        .navigationDestination(isPresented: $showLeaderboard) {
            LeaderboardView()
        }
        .navigationDestination(isPresented: $showFriends) {
            FriendSystemView()
        }
        .navigationDestination(isPresented: $showChallenges) {
            ChallengesView()
        }
        .navigationDestination(isPresented: $showAchievements) {
            AchievementsView()
        }
    }

    // MARK: - Hero Card (Level + Streak)
    // Per MODULE_ARENA.md Section 5.2 — 88pt height, #12203A background.

    private var heroCard: some View {
        HStack(spacing: TempoSpacing.md) {
            // Level badge
            ZStack {
                Circle()
                    .fill(Color.tempoSignal.opacity(0.15))
                    .frame(width: 48, height: 48)
                Text("\(viewModel?.level ?? 1)")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tempoSignal)
            }

            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text(viewModel?.levelTitle.uppercased() ?? "ROOKIE")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.tempoTextSecondary)

                // XP progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.tempoBorder)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.tempoSignal)
                            .frame(width: geo.size.width * (viewModel?.xpProgress ?? 0), height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(viewModel?.totalXP ?? 0) / \(viewModel?.xpForNextLevel ?? 100) XP")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Spacer()

            // Streak
            HStack(spacing: TempoSpacing.xs) {
                Text("🔥")
                    .font(.system(size: 20))
                Text("\(viewModel?.streakDays ?? 0)")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.tempoAmber)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(height: 88)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: 1)
        )
    }

    // MARK: - Today's XP Card
    // Per MODULE_ARENA.md Section 5.2 — Large XP number, breakdown rows.

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
                .font(.system(size: 48, weight: .bold, design: .monospaced))
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
                        Text("+\(row.xp) XP")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(row.source == .penalty ? Color.tempoError : Color.tempoSignal)
                    }
                    .frame(height: 32)
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

    // MARK: - Leaderboard Preview
    // Per MODULE_ARENA.md Section 5.2 — ~140pt, top 3 ranks.

    private var leaderboardPreviewCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Text("🏆 WEEKLY LEADERBOARD")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                Button {
                    showLeaderboard = true
                } label: {
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
                    Button {
                        showFriends = true
                    } label: {
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
            // Rank
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

            // Avatar placeholder
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
    // Per MODULE_ARENA.md Section 5.2 — ⚔️ challenge items.

    private var activeChallengesCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Text("⚔️ ACTIVE CHALLENGES")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                Button {
                    showChallenges = true
                } label: {
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
                        // Progress bar
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
    // Per MODULE_ARENA.md Section 5.2 — 🏅 horizontal scroll badges.

    private var recentAchievementsCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Text("🏅 RECENT ACHIEVEMENTS")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                Button {
                    showAchievements = true
                } label: {
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.tempoSuccess.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "star.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.tempoSuccess)
            }
            Text(achievement.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)
                .frame(width: 64)
        }
    }

    // MARK: - Challenge a Friend CTA
    // Per MODULE_ARENA.md Section 5.2 — gradient blue→purple button, 52pt.

    private var challengeCTAButton: some View {
        Button {
            showChallenges = true
        } label: {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18))
                Text("Challenge a Friend")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
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

    // MARK: - XP Detail Sheet
    // Per MODULE_ARENA.md Section 5.2 — Detailed breakdown sheet.

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

                        ForEach(breakdown.filter({ $0.source != .penalty })) { row in
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
            userStreakDays: 0 // Will be populated from UserProfile in sync
        )
    }
}
