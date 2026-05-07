//
// DashboardLoadingView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Dashboard Loading View

// Per MODULE_DASHBOARD.md Section 3.1 + WIREFRAMES.md Screen 4 — Skeleton loading state.
// Shows header (real, local data), pulsing score ring placeholder,
// 4 quadrant skeleton cards with shimmer, non-negotiables placeholder.

struct DashboardLoadingView: View {
    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // [A] Header — always shows real data (local)
            headerPlaceholder
                .padding(.top, TempoSpacing.sm)

            // [B] Score ring — pulsing track
            pulsingScoreRing
                .padding(.top, TempoSpacing.lg)

            // [C] Quadrant skeletons
            quadrantSkeletons
                .padding(.top, 20)

            // [D] Non-negotiables placeholder
            nonNegotiablesPlaceholder
                .padding(.top, 20)

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .shimmer()
    }

    // MARK: - Header Placeholder

    private var headerPlaceholder: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                skeletonRect(width: 100, height: 14)
                skeletonRect(width: 200, height: 20)
            }
            Spacer()
            HStack(spacing: TempoSpacing.sm) {
                skeletonCircle(size: 30)
                skeletonCircle(size: 30)
            }
        }
    }

    // MARK: - Pulsing Score Ring

    // Per WIREFRAMES.md Screen 4 — track pulses opacity 0.3-1.0, 1.5s sinusoidal

    private var pulsingScoreRing: some View {
        VStack(spacing: TempoSpacing.xs) {
            ZStack {
                Circle()
                    .stroke(trackColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .opacity(0.5)

                Text("--")
                    .font(.tempoScoreDisplay)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Text("Calculating...")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quadrant Skeletons

    // Per WIREFRAMES.md Screen 4 — 4 quadrant skeleton cards

    private var quadrantSkeletons: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: TempoSpacing.lg),
                GridItem(.flexible(), spacing: TempoSpacing.lg),
            ],
            spacing: TempoSpacing.lg
        ) {
            ForEach(0 ..< 4, id: \.self) { index in
                quadrantSkeletonCard(
                    label: ["BODY", "FUEL", "MIND", "MOVE"][index]
                )
            }
        }
    }

    private func quadrantSkeletonCard(label: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            // Category label (real text — per wireframe notes)
            HStack {
                Text(label)
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                skeletonCircle(size: 14)
            }

            Spacer().frame(height: TempoSpacing.xs)

            // Primary value placeholder
            skeletonRect(width: 60, height: 22)

            // Subtitle placeholder
            skeletonRect(width: 90, height: 12)

            Spacer().frame(height: TempoSpacing.xs)

            // Secondary metrics row
            HStack(spacing: TempoSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    skeletonRect(width: 36, height: 14)
                    skeletonRect(width: 30, height: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    skeletonRect(width: 36, height: 14)
                    skeletonRect(width: 30, height: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    skeletonRect(width: 36, height: 14)
                    skeletonRect(width: 30, height: 10)
                }
            }

            // Bottom bar placeholder
            skeletonRect(height: 4)
        }
        .padding(TempoSpacing.buttonPaddingV)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Non-Negotiables Placeholder

    private var nonNegotiablesPlaceholder: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            skeletonRect(width: 180, height: 14)
            skeletonRect(height: 6)
            HStack(spacing: 12) {
                skeletonRect(width: 100, height: 12)
                skeletonRect(width: 80, height: 12)
                skeletonRect(width: 90, height: 12)
            }
        }
        .padding(TempoSpacing.buttonPaddingV)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Skeleton Helpers

    private var trackColor: Color {
        colorScheme == .dark
            ? Color.tempoFillTertiary
            : Color.tempoBorder
    }

    private func skeletonRect(width: CGFloat? = nil, height: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.tempoTextDisabled.opacity(0.3))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func skeletonCircle(size: CGFloat) -> some View {
        Circle()
            .fill(Color.tempoTextDisabled.opacity(0.3))
            .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview {
    DashboardLoadingView()
        .background(Color.tempoBgPrimary)
}
