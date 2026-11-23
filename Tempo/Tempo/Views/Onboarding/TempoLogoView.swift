//
// TempoLogoView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - TempoLogoView

// Custom logo for Tempo app — a dynamic bolt inside a circle representing speed and energy

struct TempoLogoView: View {
    var size: CGFloat = 60
    var showGlow: Bool = true

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        ZStack {
            // Soft light behind the mark
            if showGlow {
                Circle()
                    .fill(mood.accent.opacity(0.35))
                    .frame(width: size * 1.1, height: size * 1.1)
                    .blur(radius: size * 0.22)
            }

            // Glass disc with an accent rim
            Circle()
                .fill(.clear)
                .frame(width: size, height: size)
                .glassEffect(.regular.tint(Tide.glassCard), in: .circle)
                .overlay {
                    Circle().strokeBorder(mood.accent.opacity(0.7), lineWidth: max(1.5, size * 0.03))
                }

            // Stylized lightning bolt
            BoltShape()
                .fill(
                    LinearGradient(
                        colors: [Tide.text, mood.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.38, height: size * 0.5)
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .accessibilityHidden(true)
    }
}

// MARK: - BoltShape

// A more stylized lightning bolt shape for the logo

struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        // Top point
        path.move(to: CGPoint(x: width * 0.55, y: 0))

        // Upper right
        path.addLine(to: CGPoint(x: width * 0.75, y: 0))

        // Angle down to middle-right
        path.addLine(to: CGPoint(x: width * 0.45, y: height * 0.45))

        // Right protrusion
        path.addLine(to: CGPoint(x: width, y: height * 0.45))

        // Angle down-left to bottom point
        path.addLine(to: CGPoint(x: width * 0.35, y: height))

        // Bottom left
        path.addLine(to: CGPoint(x: width * 0.2, y: height))

        // Angle up to middle-left
        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.55))

        // Left protrusion
        path.addLine(to: CGPoint(x: 0, y: height * 0.55))

        // Close the path back to top
        path.closeSubpath()

        return path
    }
}

// MARK: - Previews

#Preview("Default Logo") {
    TempoLogoView()
        .padding(Tide.edge)
        .tidePage()
}

#Preview("Different Sizes") {
    VStack(spacing: Tide.s8) {
        TempoLogoView(size: 40)
        TempoLogoView(size: 60)
        TempoLogoView(size: 80)
        TempoLogoView(size: 120)
    }
    .padding(Tide.edge)
    .tidePage()
}

#Preview("No Glow") {
    TempoLogoView(size: 80, showGlow: false)
        .padding(Tide.edge)
        .tidePage()
}
