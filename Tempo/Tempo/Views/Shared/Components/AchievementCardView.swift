//
// AchievementCardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Achievement Card

// Per DESIGN_SYSTEM.md Section 8.2 — Achievement Card:
// 96pt height, 16pt radius, 16pt padding. Badge icon 40pt circle with tier bg.

struct AchievementCardView: View {
    let name: String
    let description: String
    let icon: String
    let tierColor: Color
    let xpValue: Int
    let earnedDate: String?
    let isLocked: Bool

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        HStack(spacing: TempoSpacing.cardGap) {
            // Badge icon
            ZStack {
                Circle()
                    .fill(tierColor.opacity(isLocked ? 0.3 : 1.0))
                    .frame(width: 40, height: 40)
                Image(systemName: isLocked ? "lock.fill" : icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isLocked ? Color.tempoTextDisabled : Color.tempoBone)
            }

            // Text content
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(name)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(isLocked ? "Complete to unlock" : description)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                if let earnedDate, !isLocked {
                    Text(earnedDate)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            Spacer()

            // XP value
            Text("+\(xpValue)")
                .font(.tempoDataMedium)
                .foregroundStyle(Color.tempoAmber)
        }
        .padding(TempoSpacing.cardPadding)
        .frame(height: 96)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoBorder, lineWidth: TempoElevation.cardDarkBorderWidth)
                .opacity(colorScheme == .dark ? 1 : 0)
        )
        .opacity(isLocked ? 0.5 : 1.0)
    }
}
