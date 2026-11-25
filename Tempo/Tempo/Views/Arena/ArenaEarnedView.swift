//
// ArenaEarnedView.swift
// Tempo
//
// What you earned, on one page: the XP of the last days and what each came
// from, and the achievements, unlocked and next. This replaces the separate
// Achievements and Activity pages.
//
// Only achievements the app can really measure are listed (see
// ArenaAchievementTracker); every progress bar here is counted from the user's
// own records, never a placeholder.
//

import SwiftData
import SwiftUI

// MARK: - ArenaEarnedView

struct ArenaEarnedView: View {
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Query(sort: \XPEvent.date, order: .reverse)
    private var events: [XPEvent]
    @Query
    private var allAchievements: [Achievement]

    @State
    private var selectedCategory: AchievementCategory?
    @State
    private var selectedAchievement: Achievement?
    @State
    private var showsAllDays = false

    /// How many days of XP show before "Show earlier days".
    private static let collapsedDays = 4

    private var tracked: [Achievement] {
        allAchievements.filter { ArenaAchievementTracker.isTracked($0.badgeID) }
    }

    private var earnedCount: Int {
        tracked.count(where: \.isEarned)
    }

    /// Earned first (newest first), then the ones closest to unlocking.
    private var shown: [Achievement] {
        let filtered = selectedCategory.map { category in tracked.filter { $0.category == category } } ?? tracked
        return filtered.sorted { lhs, rhs in
            switch (lhs.isEarned, rhs.isEarned) {
            case (true, true): (lhs.earnedAt ?? .distantPast) > (rhs.earnedAt ?? .distantPast)
            case (true, false): true
            case (false, true): false
            case (false, false): lhs.progressFraction > rhs.progressFraction
            }
        }
    }

    private var categories: [AchievementCategory] {
        AchievementCategory.allCases.filter { category in tracked.contains { $0.category == category } }
    }

    private var days: [ArenaXPDay] {
        ArenaViewModel.days(from: events, calendar: ArenaCalendar.calendar())
    }

    /// Three across, two at accessibility sizes so names keep whole words.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Tide.s3), count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        TideScrollPage {
            hero
            activityCard
            achievementsSection
        }
        .navigationTitle("Earned")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("arena.earned")
        .sensoryFeedback(.selection, trigger: selectedAchievement?.id)
        .tideCovered(selectedAchievement != nil)
        .sheet(item: $selectedAchievement) { achievement in
            achievementDetail(achievement)
        }
    }

    // MARK: - Hero

    /// The locked achievement that is furthest along: the one to chase next.
    private var nextUp: Achievement? {
        tracked
            .filter { !$0.isEarned && !$0.isHidden && $0.targetValue > 0 && $0.progressFraction > 0 }
            .max { $0.progressFraction < $1.progressFraction }
    }

    private var hero: some View {
        let fraction = tracked.isEmpty ? 0 : Double(earnedCount) / Double(tracked.count)
        return RecoveryHero {
            TideTimerDial(progress: fraction, accent: mood.accent, diameter: Tide.dialHero) {
                VStack(spacing: 0) {
                    TideNumber("\(earnedCount)", size: Tide.numeralL, relativeTo: .title, color: mood.accent)
                    Text("of \(tracked.count)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
        } side: {
            Text("Unlocked").tideLabel()
            if let next = nextUp {
                Text("Next up").tideLabel(Tide.text3)
                Text(next.displayName)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                TideLevelBar(progress: next.progressFraction, color: next.rarity.tideTint, height: Tide.barSlim)
                Text("\(next.progressValue) / \(next.targetValue)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            } else {
                Text(earnedCount == 0 ? String(localized: "Train, study and eat well to unlock your first.") : String(localized: "Keep going."))
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(earnedCount) of \(tracked.count) achievements unlocked")
    }

    // MARK: - Activity (XP by day)

    private var activityCard: some View {
        let all = days
        let visible = showsAllDays ? all : Array(all.prefix(Self.collapsedDays))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "XP by day"))
            if all.isEmpty {
                TideEmptyPanel(
                    systemImage: "bolt.slash", title: String(localized: "No XP yet"),
                    message: String(localized: "Finish a workout, a study session or log a meal and it shows up here.")
                )
            } else {
                ForEach(visible) { day in
                    dayBlock(day)
                }
                if all.count > Self.collapsedDays {
                    TideDivider()
                    Button {
                        withAnimation(Tide.snap) { showsAllDays.toggle() }
                    } label: {
                        Text(showsAllDays ? String(localized: "Show fewer days") : String(localized: "Show earlier days"))
                            .font(Tide.bodyStrong)
                            .foregroundStyle(mood.accent)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("arena.earnedMoreDays")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .accessibilityIdentifier("arena.earnedDays")
    }

    private func dayBlock(_ day: ArenaXPDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.dayTitle(day.date))
                    .font(Tide.bodyStrong).foregroundStyle(Tide.text)
                Spacer(minLength: Tide.s2)
                TideNumber(
                    "\(day.total >= 0 ? "+" : "")\(day.total.formatted())", unit: "XP",
                    size: Tide.numeralS, relativeTo: .headline, weight: .semibold, color: mood.accent
                )
            }
            .padding(.bottom, Tide.s1)
            .accessibilityElement(children: .combine)
            ForEach(day.items) { item in
                let stacked = typeSize.isAccessibilitySize
                let layout = stacked
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                    : AnyLayout(HStackLayout(spacing: Tide.s3))
                layout {
                    HStack(spacing: Tide.s3) {
                        Image(systemName: item.source.tideSymbol)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text2)
                            .frame(width: Tide.icon)
                            .accessibilityHidden(true)
                        Text(item.text)
                            .font(Tide.body).foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !stacked {
                        Spacer(minLength: Tide.s2)
                    }
                    Text("\(item.xp >= 0 ? "+" : "")\(item.xp) XP")
                        .font(Tide.caption).foregroundStyle(Tide.text2)
                }
                .frame(maxWidth: .infinity, minHeight: Tide.hit - Tide.s2, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "Today", "Yesterday", or "Monday 24 Nov".
    static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar = ArenaCalendar.calendar()) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    // MARK: - Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "Achievements"), trailing: String(localized: "\(earnedCount) of \(tracked.count)"))
            if categories.count > 1 {
                categoryFilter
            }
            LazyVGrid(columns: columns, spacing: Tide.s4) {
                ForEach(shown, id: \.id) { achievement in
                    Button {
                        selectedAchievement = achievement
                    } label: {
                        achievementCell(achievement)
                    }
                    .buttonStyle(TideCardPressStyle())
                    .accessibilityIdentifier("arena.achievement")
                }
            }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tide.s2) {
                TideFilterChip(title: String(localized: "All"), isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(categories, id: \.self) { category in
                    TideFilterChip(title: category.displayName, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
        }
        .scrollIndicators(.hidden)
        // Chips run to the screen edge; the page's own padding is undone.
        .padding(.horizontal, -Tide.edge)
        .animation(Tide.snap, value: selectedCategory)
    }

    // Earned: full colour. Locked: muted, with a progress bar when it has a target.

    private func achievementCell(_ achievement: Achievement) -> some View {
        let tint = achievement.rarity.tideTint
        let hiddenLocked = achievement.isHidden && !achievement.isEarned
        let showsProgress = !achievement.isEarned && !achievement.isHidden && achievement.targetValue > 0
        return VStack(spacing: Tide.s2) {
            ZStack {
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .fill(achievement.isEarned ? tint.opacity(0.18) : Tide.fill)
                    .overlay {
                        if achievement.isEarned {
                            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                                .strokeBorder(tint.opacity(0.6), lineWidth: Tide.rule)
                        }
                    }
                    .shadow(color: achievement.isEarned ? tint.opacity(0.35) : .clear, radius: Tide.s3)
                Image(systemName: cellSymbol(achievement))
                    .font(Tide.title)
                    .foregroundStyle(achievement.isEarned ? tint : Tide.text3.opacity(hiddenLocked ? 1 : 0.7))
                if showsProgress {
                    VStack {
                        Spacer()
                        TideLevelBar(progress: achievement.progressFraction, color: tint, height: Tide.barSlim)
                            .padding(.horizontal, Tide.s3)
                            .padding(.bottom, Tide.s2)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if achievement.isEarned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(TideTone.mint)
                        .padding(Tide.s2)
                } else if !hiddenLocked {
                    Image(systemName: "lock.fill")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .padding(Tide.s2)
                }
            }

            VStack(spacing: Tide.hair) {
                Text(hiddenLocked ? "???" : achievement.displayName)
                    .font(Tide.caption)
                    .foregroundStyle(achievement.isEarned ? Tide.text : Tide.text2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if showsProgress {
                    Text("\(achievement.progressValue)/\(achievement.targetValue)")
                        .font(Tide.numeral(Tide.numeralS - Tide.s2, .medium))
                        .foregroundStyle(Tide.text3)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            hiddenLocked ? String(localized: "Hidden achievement")
                : achievement.isEarned
                ? String(localized: "\(achievement.displayName), \(achievement.rarity.tideName), unlocked")
                : String(localized: "\(achievement.displayName), \(achievement.rarity.tideName), locked")
        )
        .accessibilityHint("Shows details")
    }

    private func cellSymbol(_ achievement: Achievement) -> String {
        if achievement.isEarned {
            return achievement.rarity.tideSymbol
        }
        return achievement.isHidden ? "questionmark" : achievement.rarity.tideSymbol
    }

    // MARK: - Achievement Detail

    private func achievementDetail(_ achievement: Achievement) -> some View {
        let tint = achievement.rarity.tideTint
        return TideScrollPage(spacing: Tide.s5) {
            VStack(spacing: Tide.s4) {
                // The same silhouette as its tile; locked ones carry a lock badge.
                Image(systemName: achievement.rarity.tideSymbol)
                    .font(Tide.numeral(Tide.numeralM))
                    .foregroundStyle(achievement.isEarned ? tint : Tide.text3)
                    .frame(width: Tide.dialSheet, height: Tide.dialSheet)
                    .glassEffect(.regular.tint(tint.opacity(achievement.isEarned ? 0.25 : 0.12)), in: .circle)
                    .shadow(color: achievement.isEarned ? tint.opacity(0.45) : .clear, radius: Tide.s5)
                    // An earned badge opens with one burst of its rarity colour.
                    .background {
                        if achievement.isEarned {
                            ArenaBurst(accent: tint, seconds: 3.5)
                                .frame(width: Tide.dialSheet * 3, height: Tide.dialSheet * 3)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !achievement.isEarned {
                            Image(systemName: "lock.fill")
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text2)
                                .frame(width: Tide.hit, height: Tide.hit)
                                .glassEffect(.regular, in: .circle)
                        }
                    }
                    .accessibilityHidden(true)

                VStack(spacing: Tide.s2) {
                    Text(achievement.displayName)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                    Text(achievement.displayDescription)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TideStatusPill(text: achievement.rarity.tideName, tint: tint, systemImage: achievement.rarity.tideSymbol)

                if achievement.isEarned {
                    VStack(spacing: Tide.s3) {
                        VStack(spacing: Tide.s1) {
                            TideNumber("+\(achievement.effectiveXPReward)", unit: "XP", size: Tide.numeralL, color: mood.accent)
                            if let earnedAt = achievement.earnedAt {
                                Text("Earned \(earnedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(Tide.caption)
                                    .foregroundStyle(Tide.text2)
                            }
                        }
                        Button {
                            ShareCard.present(.achievement(
                                name: achievement.displayName, xp: achievement.effectiveXPReward,
                                rarity: achievement.rarity.tideName, date: achievement.earnedAt ?? Date()
                            ))
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.tideGlass)
                        .accessibilityIdentifier("arena.shareAchievement")
                    }
                } else {
                    VStack(spacing: Tide.s3) {
                        Text("Reward: \(achievement.xpReward) XP")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                        if achievement.targetValue > 0 {
                            VStack(spacing: Tide.s2) {
                                TideLevelBar(progress: achievement.progressFraction, color: tint, height: Tide.bar)
                                TideNumber(
                                    "\(achievement.progressValue)", unit: String(localized: "of \(achievement.targetValue)"),
                                    size: Tide.numeralS, relativeTo: .headline, weight: .semibold
                                )
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Tide.s6)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if achievement.isEarned {
                HapticManager.success()
            }
        }
    }
}
