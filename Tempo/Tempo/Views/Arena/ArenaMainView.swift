//
// ArenaMainView.swift
// Tempo
//
// The Arena home: your level as the hero, the weekly leaderboard right under
// it, today's XP, challenges, and what you earned. Rank and what you earned are
// the two things people check, so both are on this page; the rest opens from it.
//
// Every number here is real: XP and level come from the XPEvent rows the
// ArenaXPLedger keeps, the streak from the overall Streak row, and the board,
// friends and challenges from the server. A section with no real content shows
// a way to get some, never invented names or figures.
//

import SwiftData
import SwiftUI

// MARK: - ArenaMainView

struct ArenaMainView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(ArenaService.self)
    private var arena
    @Environment(\.modelContext)
    private var context
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State
    private var viewModel: ArenaViewModel?
    @State
    private var showXPDetail = false
    @State
    private var showInvite = false

    /// The stack's zoom namespace, so a card zooms open into its page.
    var zoom: Namespace.ID?

    init(zoom: Namespace.ID? = nil) {
        self.zoom = zoom
    }

    /// The first days of the week show last week as a recap: Monday and Tuesday.
    static func showsRecap(weekday: Int) -> Bool {
        weekday == 2 || weekday == 3
    }

    var body: some View {
        ZStack {
            if let vm = viewModel, case .loaded = vm.loadState {
                page(vm)
            } else {
                // The page's own shape, breathing, instead of a bare spinner.
                RecoverySkeleton(label: "Loading Arena")
            }

            if viewModel?.showXPGain == true {
                xpGainOverlay
            }
        }
        .tidePage(energy: 1)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("arena.home")
        .task { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await reload() }
            }
        }
        .tideCovered(showXPDetail || showInvite)
        .sheet(isPresented: $showXPDetail) {
            xpDetailSheet
        }
        .sheet(isPresented: $showInvite) {
            FriendInviteSheet()
        }
        .firstTip(
            "arena.home",
            "Tap the level ring or XP to see how it is worked out.",
            systemImage: "trophy.fill"
        )
    }

    // MARK: - Page

    // One composition, top to bottom: who you are (the level dial), where you
    // stand (leaderboard), what today is worth (the XP card), then whatever has
    // something in it. A section with nothing yet shrinks to one quiet row, so
    // a new account sees a short, calm page and a busy one a long, full page.

    private func page(_ vm: ArenaViewModel) -> some View {
        ScrollView {
            VStack(spacing: Tide.s4) {
                header(vm)
                heroCard(vm)
                    .arenaReveal(0)
                leaderboardCard
                    .arenaReveal(1)
                todayXPCard(vm)
                    .arenaReveal(2)
                if showsRecap(vm) {
                    weeklyRecapCard(vm)
                        .arenaReveal(3)
                }
                challengesSection
                    .arenaReveal(4)
                earnedCard(vm)
                    .arenaReveal(5)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s4)
            .animation(Tide.snap, value: vm.todayXP)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { await reload() }
        // The one action of the page stays under the thumb.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            mainAction
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s2)
        }
    }

    private func showsRecap(_ vm: ArenaViewModel) -> Bool {
        Self.showsRecap(weekday: Calendar.current.component(.weekday, from: Date()))
            && (vm.lastWeekXP > 0 || vm.lastWeekAchievements > 0)
    }

    // MARK: - Header

    private func header(_ vm: ArenaViewModel) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s2))
        let requests = arena.incomingRequests.count
        return layout {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(TempoDateFormatters.dashboardHeader.string(from: Date())).tideLabel()
                Text("Arena")
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: Tide.s2) {
                if vm.freezesAvailable > 0 {
                    chip(symbol: "snowflake", value: vm.freezesAvailable, tint: TideTone.sky)
                        .accessibilityLabel(ArenaText.count(vm.freezesAvailable, "streak freeze"))
                        .explains(Explainer.streakFreezes.showing("\(vm.freezesAvailable) left"))
                }
                chip(symbol: "flame.fill", value: vm.streakDays, tint: Tide.streak)
                    .accessibilityLabel("\(ArenaText.count(vm.streakDays, "day")) streak")
                    .explains(Explainer.arenaStreak.showing(ArenaText.count(vm.streakDays, "day")))
                NavigationLink(value: ArenaDestination.friends) {
                    Image(systemName: "person.2.fill")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
                        .overlay(alignment: .topTrailing) {
                            if requests > 0 {
                                Circle().fill(Tide.danger).frame(width: Tide.s3, height: Tide.s3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .tideZoomSource(id: ArenaDestination.friends, in: zoom)
                .accessibilityLabel(requests > 0 ? "Friends, \(ArenaText.count(requests, "request"))" : "Friends")
                .accessibilityIdentifier("arena.friendsButton")
            }
            // The chips take their full width first; the title gets the rest.
            .layoutPriority(1)
        }
    }

    private func chip(symbol: String, value: Int, tint: Color) -> some View {
        HStack(spacing: Tide.s1) {
            Image(systemName: symbol).font(Tide.bodyStrong).foregroundStyle(tint)
            TideNumber("\(value)", size: Tide.numeralS, relativeTo: .headline)
        }
        .padding(.horizontal, Tide.s4)
        .frame(minHeight: Tide.hit)
        .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
        .accessibilityElement(children: .ignore)
    }

    // MARK: - Hero (level, title, XP to next)

    private func heroCard(_ vm: ArenaViewModel) -> some View {
        let isMax = vm.level >= LevelSystem.definitions.count
        return RecoveryHero {
            // The ring is the way to the next level, lit like the focus dial.
            TideTimerDial(progress: vm.xpProgress, accent: mood.accent, diameter: Tide.dialHero) {
                VStack(spacing: 0) {
                    Text("Level").tideLabel()
                    TideNumber("\(vm.level)", size: Tide.numeralL, relativeTo: .title)
                }
            }
            .explains(Explainer.arenaLevel.showing("Level \(vm.level)"))
        } side: {
            Text(vm.levelTitle)
                .font(Tide.title2)
                .foregroundStyle(mood.accent)
                .lineLimit(2)
                .minimumScaleFactor(Tide.labelShrink)
            Text(isMax ? "Top level" : "\(vm.xpForNextLevel.formatted()) XP to \(vm.nextLevelTitle)")
                .font(Tide.caption).foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            // One figure everywhere: the same total as Settings and the Watch.
            TideNumber(vm.totalXP.formatted(), unit: "XP total", size: Tide.numeralS, relativeTo: .headline)
            if vm.streakDays > 0 {
                Button {
                    ShareCard.present(.streak(days: vm.streakDays, level: vm.level))
                } label: {
                    Label("Share streak", systemImage: "square.and.arrow.up")
                        .font(Tide.caption)
                        .foregroundStyle(mood.accent)
                        .frame(minHeight: Tide.hit, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("arena.shareStreak")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Leaderboard (inline)

    @ViewBuilder
    private var leaderboardCard: some View {
        switch arena.phase {
        case .idle,
             .loading:
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "This week")
                ArenaListSkeleton(rows: 2, label: "Loading leaderboard")
            }
            .tideCard()

        case let .failed(message):
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "This week")
                TideEmptyPanel(
                    systemImage: "wifi.exclamationmark", title: "Could not load the leaderboard",
                    message: message, actionTitle: "Try again"
                ) { Task { await arena.refresh() } }
            }
            .tideCard()

        case .ready:
            if arena.friends.isEmpty {
                // Nobody to race yet: three empty places and the one way to fill them.
                VStack(alignment: .leading, spacing: Tide.s4) {
                    TideSectionLabel(title: "This week")
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s4))
                    layout {
                        ArenaGhostAvatars()
                        Text("Add a friend and your weekly XP lines up against theirs.")
                            .font(Tide.bodyStrong).foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        showInvite = true
                    } label: {
                        Label("Invite a friend", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("arena.inviteButton")
                }
                .tideCard()
                .accessibilityIdentifier("arena.leaderboardEmpty")
            } else if let board = arena.leaderboard {
                let preview = Self.preview(board.rankings)
                NavigationLink(value: ArenaDestination.leaderboard) {
                    VStack(alignment: .leading, spacing: Tide.s3) {
                        TideSectionLabel(title: "This week", trailing: "See all")
                        standingLine(board)
                        VStack(spacing: Tide.s1) {
                            ForEach(preview) { entry in
                                ArenaRankRow(entry: entry)
                            }
                        }
                    }
                    .tideCard()
                    .contentShape(.rect(cornerRadius: Tide.cardRadius))
                }
                .buttonStyle(TideCardPressStyle())
                .tideZoomSource(id: ArenaDestination.leaderboard, in: zoom)
                .accessibilityHint("Opens the full leaderboard")
                .accessibilityIdentifier("arena.leaderboardCard")
            }
        }
    }

    /// The top three, plus you when you are further down.
    static func preview(_ rankings: [ArenaLeaderboardRankingDTO]) -> [ArenaLeaderboardRankingDTO] {
        var shown = Array(rankings.prefix(3))
        if let me = rankings.first(where: \.isMe), !shown.contains(where: { $0.id == me.id }) {
            shown.append(me)
        }
        return shown
    }

    /// Where you stand, in one line: your rank and the gap to the lead.
    @ViewBuilder
    private func standingLine(_ board: ArenaLeaderboardDTO) -> some View {
        if let rank = board.myRank, let lead = board.rankings.first {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                TideNumber("#\(rank)", size: Tide.numeralM, relativeTo: .title2, color: mood.accent)
                Text(rank == 1 ? "You lead the week" : "\((lead.xp - board.myXP).formatted()) XP behind \(lead.user.displayName)")
                    .font(Tide.body).foregroundStyle(Tide.text2)
                    .lineLimit(2)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Today's XP

    private func todayXPCard(_ vm: ArenaViewModel) -> some View {
        let earned = vm.todayXP > 0
        let goalMet = vm.dailyXPProgress >= 1
        return VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Today's XP")
            VStack(alignment: .leading, spacing: Tide.s2) {
                // Nothing earned yet: the goal is the number, not a "+0".
                if earned {
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                        TideNumber("+\(vm.todayXP.formatted())", size: Tide.numeralL, color: mood.accent)
                        Text("of \(vm.dailyXPGoal.formatted()) XP goal")
                            .font(Tide.body).foregroundStyle(Tide.text2)
                            .lineLimit(1).minimumScaleFactor(Tide.labelShrink)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    TideNumber(vm.dailyXPGoal.formatted(), unit: "XP daily goal", size: Tide.numeralL, color: Tide.text2)
                }
                TideLevelBar(progress: vm.dailyXPProgress, height: Tide.bar)
                if goalMet {
                    Label("Daily goal met", systemImage: "checkmark.circle.fill")
                        .font(Tide.caption)
                        .foregroundStyle(TideTone.mint)
                        .symbolEffect(.bounce, value: goalMet)
                } else if earned {
                    Text("\((vm.dailyXPGoal - vm.todayXP).formatted()) XP to your daily goal")
                        .font(Tide.caption).foregroundStyle(Tide.text2)
                }
            }
            .contentShape(.rect)
            .explains(Explainer.arenaDailyGoal.showing("\(vm.todayXP.formatted()) of \(vm.dailyXPGoal.formatted()) XP"))

            if vm.xpBreakdown.isEmpty {
                waysToEarn
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.xpBreakdown.prefix(4).enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            TideDivider()
                        }
                        xpRow(row)
                    }
                }
            }

            VStack(spacing: 0) {
                TideDivider()
                Button {
                    showXPDetail = true
                } label: {
                    HStack(spacing: Tide.s2) {
                        Text("How XP works")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(mood.accent)
                        Spacer(minLength: Tide.s2)
                        Image(systemName: "chevron.right")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("arena.xpDetail")
            }
        }
        .tideCard()
    }

    /// The first XP of the day: three things that earn it.
    private var waysToEarn: some View {
        let sideBySide = typeSize.isAccessibilitySize
        let layout = sideBySide
            ? AnyLayout(VStackLayout(spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Nothing yet today. Any of these gets you started.")
                .font(Tide.body).foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            layout {
                ArenaEarnChip(
                    systemImage: XPSource.workout.tideSymbol, title: "Train", tint: TideTone.amber,
                    sideBySide: sideBySide
                )
                ArenaEarnChip(
                    systemImage: XPSource.study.tideSymbol, title: "Study", tint: TideTone.violet,
                    sideBySide: sideBySide
                )
                ArenaEarnChip(
                    systemImage: XPSource.meal.tideSymbol, title: "Log a meal", tint: TideTone.mint,
                    sideBySide: sideBySide
                )
            }
        }
    }

    private func xpRow(_ row: XPBreakdownRow) -> some View {
        // At large text the figure drops under the name instead of breaking it mid-word.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        return layout {
            HStack(spacing: Tide.s3) {
                Image(systemName: row.source.tideSymbol)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.icon)
                    .accessibilityHidden(true)
                Text(row.label)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !stacked {
                Spacer(minLength: Tide.s2)
            }
            TideNumber(
                "+\(row.xp)", unit: "XP",
                size: Tide.numeralS, relativeTo: .headline, weight: .semibold
            )
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .padding(.vertical, stacked ? Tide.s2 : 0)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Last week (Monday and Tuesday)

    private func weeklyRecapCard(_ vm: ArenaViewModel) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Last week")
            layout {
                recapStat("XP", "+\(vm.lastWeekXP.formatted())", mood.accent)
                recapStat(vm.lastWeekWorkouts == 1 ? "Workout" : "Workouts", "\(vm.lastWeekWorkouts)", TideTone.amber)
                if vm.lastWeekAchievements > 0 {
                    recapStat("Unlocked", "\(vm.lastWeekAchievements)", TideTone.violet)
                }
            }
            Button {
                let start = ArenaCalendar.previousWeekStart(before: Date())
                ShareCard.present(.week(
                    xp: vm.lastWeekXP, workouts: vm.lastWeekWorkouts, studyMinutes: vm.lastWeekStudyMinutes,
                    weekStart: start
                ))
            } label: {
                Label("Share my week", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
            .accessibilityIdentifier("arena.shareWeek")
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private func recapStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(label).tideLabel().lineLimit(1).minimumScaleFactor(Tide.labelShrink)
            TideNumber(value, size: Tide.numeralM, relativeTo: .title2, color: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Challenges

    @ViewBuilder
    private var challengesSection: some View {
        let running = arena.runningChallenges
        let invited = arena.invitedChallenges
        if case .ready = arena.phase, !running.isEmpty || !invited.isEmpty {
            challengesCard(running: running, invited: invited)
        } else {
            NavigationLink(value: ArenaDestination.challenges) {
                ArenaLinkRow(
                    systemImage: "flag.2.crossed.fill", title: "Challenges",
                    detail: arena.phase == .ready
                        ? "None running. Start one with a friend or on your own."
                        : "Race a friend for a week, or go solo.",
                    tint: TideTone.amber
                )
                .tideCard(padding: Tide.s4)
            }
            .buttonStyle(.plain)
            .tideZoomSource(id: ArenaDestination.challenges, in: zoom)
            .accessibilityIdentifier("arena.challengesRow")
        }
    }

    private func challengesCard(running: [ArenaChallengeDTO], invited: [ArenaChallengeDTO]) -> some View {
        let shown = Array(running.prefix(2))
        return NavigationLink(value: ArenaDestination.challenges) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                TideSectionLabel(title: "Challenges", trailing: "See all")
                if !invited.isEmpty {
                    Label(
                        invited.count == 1 ? "1 invitation waiting" : "\(invited.count) invitations waiting",
                        systemImage: "envelope.badge.fill"
                    )
                    .font(Tide.bodyStrong)
                    .foregroundStyle(TideTone.amber)
                }
                ForEach(shown) { challenge in
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(challenge.title)
                                .font(Tide.headline).foregroundStyle(Tide.text)
                                .lineLimit(1)
                            Spacer(minLength: Tide.s2)
                            TideNumber(
                                challenge.metricKind?.format(challenge.myScore) ?? "\(challenge.myScore)",
                                size: Tide.numeralS, relativeTo: .headline, color: mood.accent
                            )
                        }
                        TideLevelBar(progress: challenge.timelineProgress(), height: Tide.barSlim)
                        HStack {
                            Text(challenge.timeLine())
                                .font(Tide.caption).foregroundStyle(Tide.text2)
                            Spacer(minLength: Tide.s2)
                            if let rank = challenge.myRank, challenge.memberCount > 1 {
                                Text(ArenaText.rank(rank, of: challenge.memberCount))
                                    .font(Tide.caption).foregroundStyle(Tide.text2)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if running.count > 2 {
                    Text(ArenaText.more(running.count - 2))
                        .font(Tide.caption).foregroundStyle(Tide.text2)
                }
            }
            .tideCard()
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .tideZoomSource(id: ArenaDestination.challenges, in: zoom)
        .accessibilityHint("Opens your challenges")
        .accessibilityIdentifier("arena.challengesCard")
    }

    // MARK: - Earned (achievements and activity, one page)

    private func earnedCard(_ vm: ArenaViewModel) -> some View {
        NavigationLink(value: ArenaDestination.earned) {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Earned", trailing: "See all")
                if vm.recentAchievements.isEmpty {
                    ArenaLinkRowBody(
                        systemImage: "medal.fill",
                        title: "\(vm.totalEarned) of \(vm.totalTracked) achievements",
                        detail: "Train, study and eat well to unlock your first."
                    )
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: Tide.s3) {
                            ForEach(vm.recentAchievements, id: \.id) { achievement in
                                achievementBadge(achievement)
                            }
                        }
                        // Room for the glow, so the scroll view does not clip it.
                        .padding(.vertical, Tide.s3)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .allowsHitTesting(false)
                    Text("\(vm.totalEarned) of \(vm.totalTracked) unlocked")
                        .font(Tide.caption).foregroundStyle(Tide.text2)
                }
            }
            .tideCard()
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .tideZoomSource(id: ArenaDestination.earned, in: zoom)
        .accessibilityHint("Opens your achievements and recent XP")
        .accessibilityIdentifier("arena.earnedCard")
    }

    private func achievementBadge(_ achievement: Achievement) -> some View {
        let tint = achievement.rarity.tideTint
        return VStack(spacing: Tide.s2) {
            TideAreaIconTile(systemName: achievement.rarity.tideSymbol, tint: tint, size: Tide.avatarLarge)
                // Earned: it glows, like its cell on the earned page.
                .shadow(color: tint.opacity(0.35), radius: Tide.s3)
            Text(achievement.name)
                .font(Tide.caption)
                .foregroundStyle(Tide.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: Tide.avatarLarge + Tide.s6)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The one action

    @ViewBuilder
    private var mainAction: some View {
        if case .ready = arena.phase, !arena.friends.isEmpty {
            NavigationLink(value: ArenaDestination.challenges) {
                Label("Challenge a friend", systemImage: "bolt.fill")
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("arena.challengeButton")
        } else {
            Button {
                showInvite = true
            } label: {
                Label("Invite a friend", systemImage: "person.badge.plus")
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("arena.inviteMain")
        }
    }

    // MARK: - Overlays

    private var xpGainOverlay: some View {
        TideNumber(
            "+\(viewModel?.lastXPGainAmount ?? 0)", unit: "XP",
            size: Tide.numeralL, relativeTo: .largeTitle, color: mood.accent
        )
        .padding(.horizontal, Tide.s6)
        .padding(.vertical, Tide.s3)
        .glassEffect(.regular.tint(Tide.glassCard), in: .capsule)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(Tide.snap) {
                viewModel?.showXPGain = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .sensoryFeedback(.success, trigger: viewModel?.lastXPGainAmount)
    }

    // MARK: - XP Detail Sheet

    private var xpDetailSheet: some View {
        NavigationStack {
            TideScrollPage {
                if let vm = viewModel {
                    xpSheetBody(vm)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func xpSheetBody(_ vm: ArenaViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Today's XP").tideLabel()
            if vm.todayXP > 0 {
                TideNumber("+\(vm.todayXP.formatted())", unit: "XP", size: Tide.numeralL, color: mood.accent)
            } else {
                // Nothing earned yet: say so, and point at the list below instead of a bare "+0".
                Text("Nothing on the board yet")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                Text("Do one thing from the list below and it lands here.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Tide.s4)

        if !vm.xpBreakdown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TideSectionLabel(title: "Earned today").padding(.bottom, Tide.s1)
                ForEach(Array(vm.xpBreakdown.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        TideDivider()
                    }
                    xpRow(row)
                }
            }
            .tideCard()
        }

        VStack(alignment: .leading, spacing: 0) {
            TideSectionLabel(title: "How to earn XP").padding(.bottom, Tide.s1)
            ForEach(Array(XPEngine.xpEarningCategories.enumerated()), id: \.element.id) { index, category in
                if index > 0 {
                    TideDivider()
                }
                HStack(alignment: .top, spacing: Tide.s3) {
                    Text(category.emoji)
                        .font(Tide.headline)
                        .frame(width: Tide.icon)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(category.name).font(Tide.bodyStrong).foregroundStyle(Tide.text)
                        Text(category.description).font(Tide.caption).foregroundStyle(Tide.text2)
                        // Under the description at large text, instead of squeezing the name.
                        if typeSize.isAccessibilitySize {
                            Text(category.xpRange).font(Tide.caption).foregroundStyle(mood.accent)
                        }
                    }
                    Spacer(minLength: Tide.s2)
                    if !typeSize.isAccessibilitySize {
                        Text(category.xpRange)
                            .font(Tide.caption)
                            .foregroundStyle(mood.accent)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(.vertical, Tide.s3)
                .accessibilityElement(children: .combine)
            }
        }
        .tideCard()
    }

    // MARK: - Data

    /// Brings XP in line with what the user did, shows it, tells the server,
    /// then asks it for the board. The numbers on screen never wait on the network.
    private func reload() async {
        let model = viewModel ?? ArenaViewModel(xpEngine: services.xpEngine)
        viewModel = model
        let summary = ArenaSync.syncLocal(context: context, services: services)
        model.load(in: context, summary: summary)
        await ArenaSync.push(summary, context: context, services: services)
        await arena.refresh()
    }
}

// MARK: - ArenaLinkRowBody

/// `ArenaLinkRow` without its chevron or minimum height, for use inside a card
/// that already is the link.
private struct ArenaLinkRowBody: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Tide.s3) {
            TideAreaIconTile(systemName: systemImage, tint: TideTone.violet)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title).font(Tide.bodyStrong).foregroundStyle(Tide.text)
                Text(detail).font(Tide.caption).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
