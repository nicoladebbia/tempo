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

    var body: some View {
        ZStack {
            // Outer circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.tempoSignal,
                            Color.tempoSignal.opacity(0.7),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Inner circle (darker)
            Circle()
                .fill(Color.tempoBgPrimary)
                .frame(width: size * 0.7, height: size * 0.7)

            // Stylized lightning bolt
            BoltShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.tempoSignal.opacity(0.9),
                            Color.tempoSignal,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.4, height: size * 0.5)

            // Glow effect
            if showGlow {
                Circle()
                    .fill(Color.tempoSignal.opacity(0.2))
                    .frame(width: size * 1.2, height: size * 1.2)
                    .blur(radius: 10)
            }
        }
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
        .padding()
        .background(Color.tempoBgPrimary)
}

#Preview("Different Sizes") {
    VStack(spacing: 30) {
        TempoLogoView(size: 40)
        TempoLogoView(size: 60)
        TempoLogoView(size: 80)
        TempoLogoView(size: 120)
    }
    .padding()
    .background(Color.tempoBgPrimary)
}

#Preview("No Glow") {
    TempoLogoView(size: 80, showGlow: false)
        .padding()
        .background(Color.tempoBgPrimary)
}
