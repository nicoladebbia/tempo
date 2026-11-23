//
// StaleDataIndicator.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Stale Data Indicator

// An amber dot and "Updated 20 minutes ago" once the data is older than the
// threshold (15 minutes by default). Fresh data shows nothing.

struct StaleDataIndicator: View {
    let lastUpdated: Date
    let threshold: TimeInterval

    init(lastUpdated: Date, threshold: TimeInterval = 900) {
        self.lastUpdated = lastUpdated
        self.threshold = threshold
    }

    private var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > threshold
    }

    var body: some View {
        if isStale {
            HStack(spacing: Tide.s2) {
                Circle()
                    .fill(Color.tempoWarning)
                    .frame(width: Tide.s2 - Tide.hair, height: Tide.s2 - Tide.hair)
                Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Data is stale. Last updated \(lastUpdated, format: .relative(presentation: .named))")
        }
    }
}
