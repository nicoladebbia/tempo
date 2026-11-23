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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Tide.s3), count: 3)

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

    private var summary: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Unlocked").tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber("\(earnedCount)", size: Tide.numeralL, color: mood.accent)
                Text("of \(achievements.count)")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }
            TideLevelBar(
                progress: achievements.isEmpty ? 0 : Double(earnedCount) / Double(achievements.count),
                height: Tide.bar
            )
        }
        .tideCard()
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
                Image(systemName: cellSymbol(achievement))
                    .font(Tide.title)
                    .foregroundStyle(achievement.isEarned ? tint : Tide.text3)
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
        return achievement.isHidden ? "questionmark" : "lock.fill"
    }

    // MARK: - Achievement Detail

    // Per MODULE_ARENA.md Section 11.4 — Achievement unlock detail.

    private func achievementDetail(_ achievement: Achievement) -> some View {
        let tint = achievement.rarity.tideTint
        return TideScrollPage(spacing: Tide.s5) {
            VStack(spacing: Tide.s4) {
                Image(systemName: achievement.isEarned ? achievement.rarity.tideSymbol : "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(achievement.isEarned ? tint : Tide.text2)
                    .frame(width: Tide.dialSheet, height: Tide.dialSheet)
                    .glassEffect(.regular.tint(tint.opacity(0.25)), in: .circle)
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
