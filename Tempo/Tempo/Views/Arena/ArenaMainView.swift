//
// ArenaMainView.swift
// Tempo
//
// The Arena home: your level as the hero, today's XP, the leaderboard inline,
// then challenges, achievements and activity. Everything below the hero opens
// its own page through `ArenaDestination`.
//

import SwiftData
import SwiftUI

// MARK: - Arena Main View

struct ArenaMainView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
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

    @Environment(\.modelContext)
    private var modelContext

    /// The stack's zoom namespace, so a card zooms open into its page.
    var zoom: Namespace.ID?

    init(zoom: Namespace.ID? = nil) {
        self.zoom = zoom
    }

    private var settings: UserSettings? {
        allSettings.first
    }

    /// Show weekly recap on Mondays or if toggled.
    private var shouldShowWeeklyRecap: Bool {
        Calendar.current.component(.weekday, from: Date()) == 2 // Monday
    }

    var body: some View {
        ZStack {
            switch viewModel?.loadState ?? .loading {
            case .loading:
                // The page's own shape, breathing, instead of a bare spinner.
                RecoverySkeleton(label: "Loading Arena")

            case let .error(message):
                TideEmptyPanel(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Something went wrong",
                    message: message,
                    actionTitle: "Try again",
                    action: refreshData
                )
                .tideCard()
                .padding(.horizontal, Tide.edge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded:
                if let vm = viewModel {
                    page(vm)
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
        .tidePage(energy: 1)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { refreshData() }
        .tideCovered(showXPDetail)
        .sheet(isPresented: $showXPDetail) {
            xpDetailSheet
        }
    }

    // MARK: - Page

    // One composition, top to bottom: who you are (the level dial), what today
    // is worth (the XP card), where you stand (leaderboard), then whatever has
    // something in it. A section with nothing yet shrinks to one quiet row, so
    // a new account sees a short, calm page and a busy one a long, full page.

    private func page(_ vm: ArenaViewModel) -> some View {
        ScrollView {
            VStack(spacing: Tide.s4) {
                header(vm)
                heroCard(vm)
                    .arenaReveal(0)
                if showsRecap(vm) {
                    weeklyRecapCard(vm)
                        .arenaReveal(1)
                }
                todayXPCard(vm)
                    .arenaReveal(2)
                leaderboardCard(vm)
                    .arenaReveal(3)
                if !activeChallenges.isEmpty {
                    challengesCard
                        .arenaReveal(4)
                }
                if !vm.recentAchievements.isEmpty {
                    achievementsCard(vm)
                        .arenaReveal(5)
                }
                if !activityEvents.isEmpty {
                    activityCard
                        .arenaReveal(6)
                }
                quietRows(vm)
                    .arenaReveal(7)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s4)
            .animation(Tide.snap, value: vm.todayXP)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { refreshData() }
        // The one action of the page stays under the thumb.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            challengeCTA
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s2)
        }
    }

    // MARK: - Header

    private func header(_ vm: ArenaViewModel) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s2))
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
                        .accessibilityLabel("\(vm.freezesAvailable) streak freezes")
                }
                chip(symbol: "flame.fill", value: vm.streakDays, tint: Tide.streak)
                    .accessibilityLabel("\(vm.streakDays) day streak")
                NavigationLink(value: ArenaDestination.friends) {
                    Image(systemName: "person.2.fill")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .tideZoomSource(id: ArenaDestination.friends, in: zoom)
                .accessibilityLabel("Friends")
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
        let nextLevel = vm.level + 1
        let nextName = nextLevel <= LevelSystem.definitions.count ? LevelSystem.definition(for: nextLevel).name : "Max"
        return RecoveryHero {
            // The ring is the way to the next level, lit like the focus dial.
            TideTimerDial(progress: vm.xpProgress, accent: mood.accent, diameter: Tide.dialHero) {
                VStack(spacing: 0) {
                    Text("Level").tideLabel()
                    TideNumber("\(vm.level)", size: Tide.numeralL, relativeTo: .title)
                }
            }
        } side: {
            TideStatusPill(
                text: vm.currentLeague.displayName, tint: vm.currentLeague.tideTint,
                systemImage: vm.currentLeague.iconName
            )
            Text(vm.levelTitle)
                .font(Tide.title2)
                .foregroundStyle(mood.accent)
                .lineLimit(2)
                .minimumScaleFactor(Tide.labelShrink)
            let nextRow = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s2))
            nextRow {
                Text("\(vm.xpForNextLevel.formatted()) XP to level \(nextLevel)")
                    .font(Tide.caption).foregroundStyle(Tide.text2)
                // The next rank's name only when it is a new one.
                if nextName != vm.levelTitle {
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s2)
                    }
                    Text(nextName).font(Tide.caption).foregroundStyle(Tide.text2)
                }
            }
            .minimumScaleFactor(Tide.labelShrink)
            // A bare "0 XP total" says nothing; the total shows once there is one.
            if vm.totalXP > 0 {
                TideNumber(vm.totalXP.formatted(), unit: "XP total", size: Tide.numeralS, relativeTo: .headline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Level \(vm.level), \(vm.levelTitle), \(vm.currentLeague.displayName) league. "
                + "\(vm.xpForNextLevel) XP to level \(nextLevel). \(vm.totalXP) XP total."
        )
    }

    // MARK: - Weekly Recap (Mondays, when there is something to recap)

    private func showsRecap(_ vm: ArenaViewModel) -> Bool {
        shouldShowWeeklyRecap
            && (vm.weeklyXPEarned > 0 || vm.weeklyAchievementsUnlocked > 0 || vm.weeklyRankChange != 0)
    }

    private func weeklyRecapCard(_ vm: ArenaViewModel) -> some View {
        let rank = vm.weeklyRankChange
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Last week")
            layout {
                recapStat("XP", "+\(vm.weeklyXPEarned.formatted())", mood.accent)
                if vm.weeklyAchievementsUnlocked > 0 {
                    recapStat("Unlocked", "\(vm.weeklyAchievementsUnlocked)", TideTone.violet)
                }
                if rank != 0 {
                    recapStat(
                        "Rank",
                        "\(rank > 0 ? "+" : "-")\(abs(rank))",
                        rank > 0 ? TideTone.mint : Tide.danger
                    )
                    .accessibilityLabel(rank > 0 ? "Rank up \(rank)" : "Rank down \(abs(rank))")
                }
            }
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

    // MARK: - Today's XP

    private func todayXPCard(_ vm: ArenaViewModel) -> some View {
        let earned = vm.todayXP > 0
        let goalMet = vm.dailyXPProgress >= 1
        return VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(
                title: "Today's XP",
                trailing: vm.streakMultiplier > 1.0 ? "\(multiplierText(vm.streakMultiplier))x streak bonus" : nil
            )
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
                        Text(vm.xpBreakdown.count > 4 ? "All \(vm.xpBreakdown.count) sources" : "How XP works")
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

    private func multiplierText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }

    private func xpRow(_ row: XPBreakdownRow) -> some View {
        let penalty = row.source == .penalty
        // At large text the figure drops under the name instead of breaking it mid-word.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        return layout {
            HStack(spacing: Tide.s3) {
                Image(systemName: row.source.tideSymbol)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(penalty ? Tide.danger : Tide.text2)
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
                penalty ? "\(row.xp)" : "+\(row.xp)", unit: "XP",
                size: Tide.numeralS, relativeTo: .headline, weight: .semibold,
                color: penalty ? Tide.danger : Tide.text
            )
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .padding(.vertical, stacked ? Tide.s2 : 0)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Leaderboard (inline)

    @ViewBuilder
    private func leaderboardCard(_ vm: ArenaViewModel) -> some View {
        if vm.leaderboardPreview.isEmpty {
            // Nobody to race yet: three empty places and the one way to fill them.
            VStack(alignment: .leading, spacing: Tide.s4) {
                TideSectionLabel(title: "Weekly leaderboard")
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s4))
                layout {
                    ArenaGhostAvatars()
                    Text("Add friends to compete.")
                        .font(Tide.bodyStrong).foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NavigationLink(value: ArenaDestination.friends) {
                    Label("Invite friends", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
            }
            .tideCard()
        } else {
            NavigationLink(value: ArenaDestination.leaderboard) {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    TideSectionLabel(title: "Weekly leaderboard", trailing: "See all")
                    standingLine(vm.leaderboardPreview)
                    VStack(spacing: Tide.s1) {
                        ForEach(vm.leaderboardPreview) { entry in
                            leaderboardRow(entry)
                        }
                    }
                }
                .tideCard()
                .contentShape(.rect(cornerRadius: Tide.cardRadius))
            }
            .buttonStyle(TideCardPressStyle())
            .tideZoomSource(id: ArenaDestination.leaderboard, in: zoom)
            .accessibilityHint("Opens the full leaderboard")
        }
    }

    /// Where you stand, in one line: your rank and the gap to the lead.
    @ViewBuilder
    private func standingLine(_ entries: [LeaderboardEntry]) -> some View {
        if let me = entries.first(where: \.isMe), let lead = entries.first(where: { $0.rank == 1 }) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                TideNumber("#\(me.rank)", size: Tide.numeralM, relativeTo: .title2, color: mood.accent)
                Text(me.rank == 1 ? "You lead the week" : "\((lead.xp - me.xp).formatted()) XP behind \(lead.displayName)")
                    .font(Tide.body).foregroundStyle(Tide.text2)
                    .lineLimit(2)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func leaderboardRow(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: Tide.s3) {
            Group {
                if entry.rank == 1 {
                    Image(systemName: "crown.fill").font(Tide.bodyStrong).foregroundStyle(TideTone.gold)
                } else {
                    TideNumber("\(entry.rank)", size: Tide.numeralS, relativeTo: .headline, color: Tide.text2)
                }
            }
            .frame(minWidth: Tide.s6)
            TideInitialAvatar(name: entry.displayName, size: Tide.avatar - Tide.s1)
            Text(entry.isMe ? "You" : entry.displayName)
                .font(Tide.bodyStrong)
                .foregroundStyle(entry.isMe ? mood.accent : Tide.text)
                .lineLimit(1)
            Spacer(minLength: Tide.s2)
            TideNumber(
                entry.xp.formatted(), unit: "XP", size: Tide.numeralS, relativeTo: .headline,
                weight: .semibold, color: Tide.text
            )
        }
        .frame(minHeight: Tide.hit)
        .padding(.horizontal, Tide.s2)
        .background(
            entry.isMe ? mood.accent.opacity(0.14) : .clear,
            in: .rect(cornerRadius: Tide.controlRadius)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(entry.rank), \(entry.isMe ? "you" : entry.displayName), \(entry.xp) XP")
    }

    // MARK: - Challenges

    private var challengesCard: some View {
        let shown = Array(activeChallenges.prefix(2))
        return NavigationLink(value: ArenaDestination.challenges) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                TideSectionLabel(title: "Challenges", trailing: "See all")
                ForEach(shown, id: \.id) { challenge in
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(challenge.name)
                                .font(Tide.headline).foregroundStyle(Tide.text)
                                .lineLimit(1)
                            Spacer(minLength: Tide.s2)
                            TideNumber(
                                challenge.myScore.formatted(.number.precision(.fractionLength(0))),
                                size: Tide.numeralS, relativeTo: .headline, color: mood.accent
                            )
                        }
                        TideLevelBar(progress: challenge.timelineProgress, height: Tide.barSlim)
                        HStack {
                            Text("\(challenge.daysRemaining) days left")
                                .font(Tide.caption).foregroundStyle(Tide.text2)
                            Spacer(minLength: Tide.s2)
                            if let rank = challenge.myRank, let total = challenge.participantCount, total > 1 {
                                Text("#\(rank) of \(total)")
                                    .font(Tide.caption).foregroundStyle(Tide.text2)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if activeChallenges.count > 2 {
                    Text("+\(activeChallenges.count - 2) more")
                        .font(Tide.caption).foregroundStyle(Tide.text2)
                }
            }
            .tideCard()
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .tideZoomSource(id: ArenaDestination.challenges, in: zoom)
        .accessibilityHint("Opens your challenges")
    }

    // MARK: - Achievements

    private func achievementsCard(_ vm: ArenaViewModel) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            NavigationLink(value: ArenaDestination.achievements) {
                TideSectionLabel(title: "Recent achievements", trailing: "See all")
                    .frame(minHeight: Tide.hit - Tide.s4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
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
        }
        .tideCard()
        .tideZoomSource(id: ArenaDestination.achievements, in: zoom)
    }

    private func achievementBadge(_ achievement: Achievement) -> some View {
        let tint = achievement.rarity.tideTint
        return VStack(spacing: Tide.s2) {
            TideAreaIconTile(systemName: achievement.rarity.tideSymbol, tint: tint, size: Tide.avatarLarge)
                // Earned: it glows, like its cell on the achievements page.
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

    // MARK: - Activity

    private var activityCard: some View {
        NavigationLink(value: ArenaDestination.activityFeed) {
            VStack(alignment: .leading, spacing: Tide.s2) {
                TideSectionLabel(title: "Recent activity", trailing: "See all")
                ForEach(Array(activityEvents.prefix(3)), id: \.id) { event in
                    HStack(spacing: Tide.s3) {
                        Image(systemName: event.iconName)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(mood.accent)
                            .frame(width: Tide.icon)
                            .accessibilityHidden(true)
                        Text(event.title)
                            .font(Tide.body).foregroundStyle(Tide.text)
                            .lineLimit(1)
                        Spacer(minLength: Tide.s2)
                        Text(event.timeAgo)
                            .font(Tide.caption).foregroundStyle(Tide.text2)
                            .lineLimit(1)
                    }
                    .frame(minHeight: Tide.hit - Tide.s2)
                    .accessibilityElement(children: .combine)
                }
            }
            .tideCard()
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .tideZoomSource(id: ArenaDestination.activityFeed, in: zoom)
        .accessibilityHint("Opens your activity")
    }

    // MARK: - Sections with nothing in them yet

    /// Challenges, achievements and activity that are still empty collapse into
    /// one card of rows, instead of one card each saying "nothing here".
    @ViewBuilder
    private func quietRows(_ vm: ArenaViewModel) -> some View {
        let noChallenges = activeChallenges.isEmpty
        let noAchievements = vm.recentAchievements.isEmpty
        let noActivity = activityEvents.isEmpty
        if noChallenges || noAchievements || noActivity {
            VStack(spacing: 0) {
                if noChallenges {
                    quietRow(
                        .challenges, systemImage: "flag.2.crossed.fill", title: "Challenges",
                        detail: "None active. Start one with a friend or on your own."
                    )
                }
                if noChallenges, noAchievements || noActivity {
                    TideDivider()
                }
                if noAchievements {
                    quietRow(
                        .achievements, systemImage: "medal.fill", title: "Achievements",
                        detail: "\(vm.totalEarned) of \(achievements.count) unlocked"
                    )
                }
                if noAchievements, noActivity {
                    TideDivider()
                }
                if noActivity {
                    quietRow(
                        .activityFeed, systemImage: "bolt.fill", title: "Activity",
                        detail: "Your activity will appear here."
                    )
                }
            }
            .tideCard(padding: Tide.s4)
        }
    }

    private func quietRow(_ destination: ArenaDestination, systemImage: String, title: String, detail: String) -> some View {
        NavigationLink(value: destination) {
            ArenaLinkRow(systemImage: systemImage, title: title, detail: detail)
        }
        .buttonStyle(.plain)
        .tideZoomSource(id: destination, in: zoom)
    }

    // MARK: - Challenge a friend

    private var challengeCTA: some View {
        NavigationLink(value: ArenaDestination.challenges) {
            Label("Challenge a friend", systemImage: "bolt.fill")
        }
        .buttonStyle(.tidePrimary)
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(Tide.snap) {
                    viewModel?.showXPGain = false
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .sensoryFeedback(.success, trigger: viewModel?.lastXPGainAmount)
    }

    private var freezeSavedOverlay: some View {
        VStack(spacing: Tide.s2) {
            Image(systemName: "snowflake")
                .font(Tide.title)
                .foregroundStyle(TideTone.sky)
            Text("Freeze saved your streak")
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
        }
        .padding(Tide.s6)
        .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: Tide.cardRadius))
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(Tide.snap) {
                    viewModel?.showFreezeSaved = false
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
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
        let earned = vm.xpBreakdown.filter { $0.source != .penalty }
        let penalties = vm.xpBreakdown.filter { $0.source == .penalty }
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Today's XP").tideLabel()
            let streakPill = vm.streakMultiplier > 1.0
                ? TideStatusPill(
                    text: "\(multiplierText(vm.streakMultiplier))x streak",
                    tint: Tide.streak, systemImage: "flame.fill"
                )
                : nil
            if vm.todayXP > 0 {
                // The streak pill goes under the figure at large text, where it was cut short.
                let headline = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s2))
                headline {
                    TideNumber("+\(vm.todayXP.formatted())", unit: "XP", size: Tide.numeralL, color: mood.accent)
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                    }
                    if let streakPill {
                        streakPill
                    }
                }
            } else {
                // Nothing earned yet: say so, and point at the list below instead of a bare "+0".
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Nothing on the board yet")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                    Text("Do one thing from the list below and it lands here.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let streakPill {
                        streakPill
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Tide.s4)

        if !earned.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TideSectionLabel(title: "Earned").padding(.bottom, Tide.s1)
                ForEach(Array(earned.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        TideDivider()
                    }
                    xpRow(row)
                }
            }
            .tideCard()
        }
        if !penalties.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TideSectionLabel(title: "Penalties").padding(.bottom, Tide.s1)
                ForEach(Array(penalties.enumerated()), id: \.element.id) { index, row in
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
