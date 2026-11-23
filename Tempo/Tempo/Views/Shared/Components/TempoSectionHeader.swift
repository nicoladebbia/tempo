//
// TempoSectionHeader.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - Tempo Section Header

// Standardized section header used across Recovery module and beyond.
// Replaces inline Text headers and colored-dot variants for consistency.

struct TempoSectionHeader: View {
    let title: String
    var accentColor: Color?

    init(_ title: String, accentColor: Color? = nil) {
        self.title = title
        self.accentColor = accentColor
    }

    var body: some View {
        HStack(spacing: Tide.s2) {
            if let accentColor {
                Circle()
                    .fill(accentColor)
                    .frame(width: Tide.s2, height: Tide.s2)
            }

            Text(title)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
        }
    }
}
