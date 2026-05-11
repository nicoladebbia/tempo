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
        HStack(spacing: TempoSpacing.xs) {
            if let accentColor {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
            }

            Text(title)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }
}
