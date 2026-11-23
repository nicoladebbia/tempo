//
// AchievementCardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Achievement Card

// A badge in its tier colour, the name and what it takes, and the XP it paid.
// A locked badge dims and shows what to do to unlock it.

struct AchievementCardView: View {
    let name: String
    let description: String
    let icon: String
    let tierColor: Color
    let xpValue: Int
    let earnedDate: String?
    let isLocked: Bool

    var body: some View {
        HStack(spacing: Tide.s4) {
            Image(systemName: isLocked ? "lock.fill" : icon)
                .font(Tide.headline)
                .foregroundStyle(isLocked ? Tide.text3 : Tide.ink)
                .frame(width: Tide.s10 + Tide.s1, height: Tide.s10 + Tide.s1)
                .background(isLocked ? tierColor.opacity(0.28) : tierColor, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isLocked ? "Complete to unlock" : description)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let earnedDate, !isLocked {
                    Text(earnedDate)
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                }
            }

            Spacer(minLength: Tide.s2)

            TideNumber("+\(xpValue)", unit: "XP", size: Tide.numeralS, relativeTo: .headline, color: Tide.carbs)
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .opacity(isLocked ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}
