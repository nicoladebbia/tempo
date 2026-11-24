//
// AchievementsView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Achievements View

// Per MODULE_ARENA.md Section 10 — Grid of 108 achievements.
// Per WIREFRAMES.md Screen 40 — 3-column grid, earned/locked states.

struct AchievementsView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Query
    private var achievements: [Achievement]

    @State
    private var selectedCategory: AchievementCategory? = nil
    @State
    private var selectedAchievement: Achievement?

    private var earnedCount: Int {
        achievements.count(where: { $0.isEarned })
    }

    private var filteredAchievements: [Achievement] {
        guard let category = selectedCategory else {
            return achievements
        }
        return achievements.filter { $0.category == category }
    }

    /// Three across, two at accessibility sizes so names keep whole words.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Tide.s3), count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        TideScrollPage {
            summary
            categoryFilter
            LazyVGrid(columns: columns, spacing: Tide.s4) {
                ForEach(filteredAchievements, id: \.id) { achievement in
                    Button {
                        selectedAchievement = achievement
                    } label: {
                        achievementCell(achievement)
                    }
                    .buttonStyle(TideCardPressStyle())
                }
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selectedAchievement?.id)
        .tideCovered(selectedAchievement != nil)
        .sheet(item: $selectedAchievement) { achievement in
            achievementDetail(achievement)
        }
    }

    // MARK: - Summary

    /// The locked achievement that is furthest along: the one to chase next.
    private var nextUp: Achievement? {
        achievements
            .filter { !$0.isEarned && !$0.isHidden && $0.targetValue > 0 && $0.progressFraction > 0 }
            .max { $0.progressFraction < $1.progressFraction }
    }

    private var summary: some View {
        let fraction = achievements.isEmpty ? 0 : Double(earnedCount) / Double(achievements.count)
        return RecoveryHero {
            TideTimerDial(progress: fraction, accent: mood.accent, diameter: Tide.dialHero) {
                VStack(spacing: 0) {
                    TideNumber("\(earnedCount)", size: Tide.numeralL, relativeTo: .title, color: mood.accent)
                    Text("of \(achievements.count)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
        } side: {
            Text("Unlocked").tideLabel()
            if let next = nextUp {
                Text("Next up").tideLabel(Tide.text3)
                Text(next.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                TideLevelBar(progress: next.progressFraction, color: next.rarity.tideTint, height: Tide.barSlim)
                Text("\(next.progressValue) / \(next.targetValue)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            } else {
                Text(earnedCount == 0 ? "Train, study and eat well to unlock your first." : "Keep going.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(earnedCount) of \(achievements.count) unlocked")
    }

    // MARK: - Category Filter

    // Per WIREFRAMES.md Screen 40 — Horizontal scroll pills.

    private var categoryFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tide.s2) {
                TideFilterChip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(AchievementCategory.allCases.filter { $0 != .hidden }, id: \.self) { category in
                    TideFilterChip(title: category.rawValue.capitalized, isSelected: selectedCategory == category) {
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

    // MARK: - Achievement Cell

    // Per WIREFRAMES.md Screen 40 — 3-column grid.
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
                Text(hiddenLocked ? "???" : achievement.name)
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
            hiddenLocked ? "Hidden achievement"
                : "\(achievement.name), \(achievement.rarity.tideName), \(achievement.isEarned ? "unlocked" : "locked")"
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

    // Per MODULE_ARENA.md Section 11.4 — Achievement unlock detail.

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
                    Text(achievement.name)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                    Text(achievement.achievementDescription)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TideStatusPill(text: achievement.rarity.tideName, tint: tint, systemImage: achievement.rarity.tideSymbol)

                if achievement.isEarned {
                    VStack(spacing: Tide.s1) {
                        TideNumber("+\(achievement.effectiveXPReward)", unit: "XP", size: Tide.numeralL, color: mood.accent)
                        if let earnedAt = achievement.earnedAt {
                            Text("Earned \(earnedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                    }
                } else {
                    VStack(spacing: Tide.s3) {
                        Text("Reward: \(achievement.xpReward) XP")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                        // Progress toward unlocking
                        if achievement.targetValue > 0 {
                            VStack(spacing: Tide.s2) {
                                TideLevelBar(progress: achievement.progressFraction, color: tint, height: Tide.bar)
                                TideNumber(
                                    "\(achievement.progressValue)", unit: "of \(achievement.targetValue)",
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
    }
}
