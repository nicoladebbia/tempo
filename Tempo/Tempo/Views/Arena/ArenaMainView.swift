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
                ProgressView()
                    .controlSize(.large)
                    .tint(Tide.text2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading Arena")

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

    private func page(_ vm: ArenaViewModel) -> some View {
        ScrollView {
            VStack(spacing: Tide.s4) {
                header(vm)
                heroCard(vm)
                if shouldShowWeeklyRecap {
                    weeklyRecapCard(vm)
                }
                todayXPCard(vm)
                leaderboardCard(vm)
                challengesCard
                achievementsCard(vm)
                activityCard
                challengeCTA
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
            .animation(Tide.snap, value: vm.todayXP)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { refreshData() }
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
        return VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Level").tideLabel()
                Spacer(minLength: Tide.s2)
                TideStatusPill(
                    text: vm.currentLeague.displayName, tint: vm.currentLeague.tideTint,
                    systemImage: vm.currentLeague.iconName
                )
            }
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                TideNumber("\(vm.level)", size: Tide.numeralHero, relativeTo: .largeTitle)
                Text(vm.levelTitle)
                    .font(Tide.title2)
                    .foregroundStyle(mood.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            VStack(alignment: .leading, spacing: Tide.s2) {
                TideLevelBar(progress: vm.xpProgress, height: Tide.bar)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(vm.xpForNextLevel.formatted()) XP to level \(nextLevel)")
                        .font(Tide.caption).foregroundStyle(Tide.text2)
                    Spacer(minLength: Tide.s2)
                    Text(nextName).font(Tide.caption).foregroundStyle(Tide.text2)
                }
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            }
            TideDivider()
            TideNumber(vm.totalXP.formatted(), unit: "XP total", size: Tide.numeralS, relativeTo: .headline)
        }
        .tideCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Level \(vm.level), \(vm.levelTitle), \(vm.currentLeague.displayName) league. "
                + "\(vm.xpForNextLevel) XP to level \(nextLevel). \(vm.totalXP) XP total."
        )
    }

    // MARK: - Weekly Recap (Mondays)

    private func weeklyRecapCard(_ vm: ArenaViewModel) -> some View {
        let rank = vm.weeklyRankChange
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Last week")
            // XP gets a full row: a week's total can run to five digits, which
            // would not fit one quarter of the card.
            recapStat("XP", "+\(vm.weeklyXPEarned.formatted())", mood.accent)
            layout {
                recapStat("Unlocked", "\(vm.weeklyAchievementsUnlocked)", TideTone.violet)
                recapStat(
                    "Rank",
                    rank == 0 ? "0" : "\(rank > 0 ? "+" : "-")\(abs(rank))",
                    rank >= 0 ? TideTone.mint : Tide.danger
                )
                .accessibilityLabel(rank > 0 ? "Rank up \(rank)" : rank < 0 ? "Rank down \(abs(rank))" : "Rank unchanged")
                recapStat("Streak", "\(vm.streakDays)", Tide.streak)
            }
        }
        .tideCard()
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
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(
                title: "Today's XP",
                trailing: vm.streakMultiplier > 1.0 ? "\(multiplierText(vm.streakMultiplier))x streak bonus" : nil
            )
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    TideNumber("+\(vm.todayXP.formatted())", size: Tide.numeralL, color: mood.accent)
                    Text("of \(vm.dailyXPGoal.formatted()) XP goal")
                        .font(Tide.body).foregroundStyle(Tide.text2)
                        .lineLimit(1).minimumScaleFactor(Tide.labelShrink)
                }
                .accessibilityElement(children: .combine)
                TideLevelBar(progress: vm.dailyXPProgress, height: Tide.bar)
            }

            if vm.xpBreakdown.isEmpty {
                Text("Train, study or log a meal to earn XP.")
                    .font(Tide.body).foregroundStyle(Tide.text2)
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

            Button {
                showXPDetail = true
            } label: {
                Label(
                    vm.xpBreakdown.count > 4 ? "All \(vm.xpBreakdown.count) sources" : "How XP works",
                    systemImage: "list.bullet"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
        }
        .tideCard()
    }

    private func multiplierText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }

    private func xpRow(_ row: XPBreakdownRow) -> some View {
        let penalty = row.source == .penalty
        return HStack(spacing: Tide.s3) {
            Image(systemName: row.source.tideSymbol)
                .font(Tide.bodyStrong)
                .foregroundStyle(penalty ? Tide.danger : Tide.text2)
                .frame(width: Tide.icon)
                .accessibilityHidden(true)
            Text(row.label).font(Tide.body).foregroundStyle(Tide.text)
            Spacer(minLength: Tide.s2)
            TideNumber(
                penalty ? "\(row.xp)" : "+\(row.xp)", unit: "XP",
                size: Tide.numeralS, relativeTo: .headline, weight: .semibold,
                color: penalty ? Tide.danger : Tide.text
            )
        }
        .frame(minHeight: Tide.hit)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Leaderboard (inline)

    @ViewBuilder
    private func leaderboardCard(_ vm: ArenaViewModel) -> some View {
        if vm.leaderboardPreview.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Weekly leaderboard")
                Text("Add friends to compete.")
                    .font(Tide.body).foregroundStyle(Tide.text2)
                NavigationLink(value: ArenaDestination.friends) {
                    Label("Invite friends", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
            }
            .tideCard()
        } else {
            NavigationLink(value: ArenaDestination.leaderboard) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    TideSectionLabel(title: "Weekly leaderboard", trailing: "See all")
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

    @ViewBuilder
    private var challengesCard: some View {
        if activeChallenges.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Challenges")
                Text("No active challenges. Start one with a friend or on your own.")
                    .font(Tide.body).foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink(value: ArenaDestination.challenges) {
                    Label("See challenges", systemImage: "flag.2.crossed.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
            }
            .tideCard()
        } else {
            let shown = Array(activeChallenges.prefix(2))
            NavigationLink(value: ArenaDestination.challenges) {
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
                            Text("\(challenge.daysRemaining) days left")
                                .font(Tide.caption).foregroundStyle(Tide.text2)
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
    }

    // MARK: - Achievements

    @ViewBuilder
    private func achievementsCard(_ vm: ArenaViewModel) -> some View {
        if vm.recentAchievements.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Achievements")
                Text("Finish your daily tasks to unlock your first one.")
                    .font(Tide.body).foregroundStyle(Tide.text2)
                NavigationLink(value: ArenaDestination.achievements) {
                    Label("See all achievements", systemImage: "medal.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
            }
            .tideCard()
        } else {
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
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .tideCard()
            .tideZoomSource(id: ArenaDestination.achievements, in: zoom)
        }
    }

    private func achievementBadge(_ achievement: Achievement) -> some View {
        VStack(spacing: Tide.s2) {
            TideAreaIconTile(
                systemName: achievement.rarity.tideSymbol, tint: achievement.rarity.tideTint,
                size: Tide.avatarLarge
            )
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
                if activityEvents.isEmpty {
                    Text("Your activity will appear here.")
                        .font(Tide.body).foregroundStyle(Tide.text2)
                } else {
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
            }
            .tideCard()
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .tideZoomSource(id: ArenaDestination.activityFeed, in: zoom)
        .accessibilityHint("Opens your activity")
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
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber("+\(vm.todayXP.formatted())", unit: "XP", size: Tide.numeralL, color: mood.accent)
                Spacer(minLength: 0)
                if vm.streakMultiplier > 1.0 {
                    TideStatusPill(
                        text: "\(multiplierText(vm.streakMultiplier))x streak",
                        tint: Tide.streak, systemImage: "flame.fill"
                    )
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
                    }
                    Spacer(minLength: Tide.s2)
                    Text(category.xpRange)
                        .font(Tide.caption)
                        .foregroundStyle(mood.accent)
                        .multilineTextAlignment(.trailing)
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
