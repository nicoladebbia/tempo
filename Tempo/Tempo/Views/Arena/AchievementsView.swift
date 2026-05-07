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

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header count
            headerCount

            // Category filter
            categoryFilter

            // Grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredAchievements, id: \.id) { achievement in
                        achievementCell(achievement)
                            .onTapGesture {
                                selectedAchievement = achievement
                            }
                    }
                }
                .padding(.horizontal, TempoSpacing.lg)
                .padding(.bottom, TempoSpacing.xxxl)
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("ACHIEVEMENTS")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedAchievement) { achievement in
            achievementDetail(achievement)
        }
    }

    // MARK: - Header Count

    private var headerCount: some View {
        Text("\(earnedCount) / \(achievements.count) UNLOCKED")
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Color.tempoTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.vertical, TempoSpacing.sm)
    }

    // MARK: - Category Filter

    // Per WIREFRAMES.md Screen 40 — Horizontal scroll pills.

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TempoSpacing.sm) {
                filterPill(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(AchievementCategory.allCases.filter { $0 != .hidden }, id: \.self) { category in
                    filterPill(title: category.rawValue.capitalized, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.lg)
        }
        .padding(.bottom, TempoSpacing.md)
    }

    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.tempoTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.tempoSignal : Color.tempoSurfaceCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.tempoBorder, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Achievement Cell

    // Per WIREFRAMES.md Screen 40 — 80x100pt each, 3-column grid.
    // Earned: full color + checkmark. Locked: gray tint + lock icon.

    private func achievementCell(_ achievement: Achievement) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(achievement.isEarned ? rarityColor(achievement.rarity).opacity(0.15) : Color.tempoSteel.opacity(0.1))
                    .frame(width: 80, height: 80)

                if achievement.isEarned {
                    Image(systemName: rarityIcon(achievement.rarity))
                        .font(.system(size: 28))
                        .foregroundStyle(rarityColor(achievement.rarity))
                } else if achievement.isHidden, !achievement.isEarned {
                    Image(systemName: "questionmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.tempoSteel.opacity(0.4))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.tempoSteel.opacity(0.4))
                }

                // Earned checkmark
                if achievement.isEarned {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.tempoSuccess)
                                .background(Circle().fill(Color.tempoBgPrimary).frame(width: 18, height: 18))
                        }
                        Spacer()
                    }
                    .frame(width: 80, height: 80)
                    .padding(4)
                }

                // Progress bar for locked achievements with a target
                if !achievement.isEarned, !achievement.isHidden, achievement.targetValue > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.tempoSteel.opacity(0.2))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(rarityColor(achievement.rarity).opacity(0.7))
                                    .frame(width: geo.size.width * achievement.progressFraction, height: 4)
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }
                    .frame(width: 80, height: 80)
                }
            }

            VStack(spacing: 2) {
                Text(achievement.isHidden && !achievement.isEarned ? "???" : achievement.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(achievement.isEarned ? Color.tempoTextPrimary : Color.tempoTextTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)

                // Progress label for locked achievements
                if !achievement.isEarned, !achievement.isHidden, achievement.targetValue > 0 {
                    Text("\(achievement.progressValue)/\(achievement.targetValue)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .frame(height: 28)
        }
        .frame(height: 120)
    }

    // MARK: - Achievement Detail

    // Per MODULE_ARENA.md Section 11.4 — Achievement unlock detail.

    private func achievementDetail(_ achievement: Achievement) -> some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            // Badge
            ZStack {
                Circle()
                    .fill(rarityColor(achievement.rarity).opacity(0.15))
                    .frame(width: 120, height: 120)

                if achievement.isEarned {
                    Image(systemName: rarityIcon(achievement.rarity))
                        .font(.system(size: 48))
                        .foregroundStyle(rarityColor(achievement.rarity))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.tempoSteel)
                }
            }

            // Info
            VStack(spacing: TempoSpacing.sm) {
                Text(achievement.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.tempoTextPrimary)

                Text(achievement.achievementDescription)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)

                // Rarity
                Text(achievement.rarity.rawValue.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(rarityColor(achievement.rarity))

                if achievement.isEarned {
                    Text("+\(achievement.effectiveXPReward) XP")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoSignal)

                    if let earnedAt = achievement.earnedAt {
                        Text("Earned \(earnedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                } else {
                    Text("XP Reward: \(achievement.xpReward)")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoTextTertiary)

                    // Progress toward unlocking
                    if achievement.targetValue > 0 {
                        VStack(spacing: TempoSpacing.xs) {
                            LinearProgressBar(
                                progress: achievement.progressFraction,
                                label: "Progress",
                                color: rarityColor(achievement.rarity),
                                height: 8,
                                showPercentage: false
                            )
                            Text("\(achievement.progressValue) / \(achievement.targetValue)")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                        .padding(.horizontal, TempoSpacing.lg)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.xxl)
        .background(Color.tempoBgPrimary)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Rarity Helpers

    private func rarityColor(_ rarity: AchievementRarity) -> Color {
        switch rarity {
        case .common: Color.tempoSteel
        case .uncommon: Color.tempoSuccess
        case .rare: Color.tempoSignal
        case .epic: Color.tempoViolet
        case .legendary: Color.tempoAmber
        }
    }

    private func rarityIcon(_ rarity: AchievementRarity) -> String {
        switch rarity {
        case .common: "star.fill"
        case .uncommon: "star.fill"
        case .rare: "star.circle.fill"
        case .epic: "shield.checkered"
        case .legendary: "crown.fill"
        }
    }
}
