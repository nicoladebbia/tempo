//
// WorkoutCardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Workout Card

// Name and length of a session on a glass card: the muscle groups sit under
// it as small chips, the figures as condensed numerals.

struct WorkoutCardView: View {
    let name: String
    let exerciseCount: Int
    let estimatedMinutes: Int
    let muscleGroups: [String]
    let action: () -> Void

    @State
    private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(alignment: .leading, spacing: Tide.s3) {
                HStack(spacing: Tide.s3) {
                    TideIconTile(systemName: "dumbbell.fill", size: Tide.tile)
                    Text(name)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    TideNumber("\(estimatedMinutes)", unit: "min", size: Tide.numeralS, relativeTo: .headline)
                }

                Text("\(exerciseCount) exercises")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)

                if !muscleGroups.isEmpty {
                    FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                        ForEach(muscleGroups, id: \.self) { group in
                            Text(group)
                                .tideLabel()
                                .padding(.horizontal, Tide.s3)
                                .padding(.vertical, Tide.s1)
                                .background(Tide.fill, in: .capsule)
                        }
                    }
                }
            }
            .tideCard()
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityElement(children: .combine)
    }
}
