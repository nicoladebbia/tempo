//
// PrescriptionCardView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Prescription Card (Drill Sergeant Message)

// The drill sergeant's order of the day on a glass card, with when it was said.

struct PrescriptionCardView: View {
    let message: String
    let timestamp: String

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            TideIconTile(systemName: "megaphone.fill", size: Tide.tile)

            VStack(alignment: .leading, spacing: Tide.s1) {
                HStack(alignment: .firstTextBaseline) {
                    TideLabel("Drill sergeant", color: mood.accent)
                    Spacer(minLength: Tide.s2)
                    Text(timestamp)
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                }

                Text(message)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}
