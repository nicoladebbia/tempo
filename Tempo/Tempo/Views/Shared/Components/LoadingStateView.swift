//
// LoadingStateView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Loading State View

// Skeletons drawn as the glass cards they stand in for, breathing slowly
// instead of sweeping. Reduce Motion holds them still.

struct LoadingStateView: View {
    let style: LoadingStyle

    enum LoadingStyle {
        case cards
        case quadrants
        case list

        var itemCount: Int {
            switch self {
            case .cards: 3
            case .quadrants: 4
            case .list: 5
            }
        }
    }

    init(style: LoadingStyle = .cards) {
        self.style = style
    }

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var dim = false

    var body: some View {
        GlassEffectContainer(spacing: Tide.s3) {
            switch style {
            case .cards:
                cardSkeletons
            case .quadrants:
                quadrantSkeletons
            case .list:
                listSkeletons
            }
        }
        .opacity(dim ? 0.55 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    // MARK: - Card Skeletons

    private var cardSkeletons: some View {
        VStack(spacing: Tide.s3) {
            ForEach(0 ..< style.itemCount, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Tide.s3) {
                    skeletonRect(width: 96, height: 10)
                    skeletonRect(height: 20)
                    skeletonRect(width: 200, height: 12)
                }
                .tideCard()
            }
        }
    }

    // MARK: - Quadrant Skeletons

    private var quadrantSkeletons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Tide.s3) {
            ForEach(0 ..< style.itemCount, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Tide.s2) {
                    skeletonRect(width: 72, height: 10)
                    Spacer()
                    skeletonRect(width: 60, height: 24)
                    skeletonRect(width: 100, height: 10)
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    // MARK: - List Skeletons

    private var listSkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< style.itemCount, id: \.self) { _ in
                HStack(spacing: Tide.s3) {
                    Circle()
                        .fill(Tide.fill)
                        .frame(width: Tide.s10, height: Tide.s10)
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        skeletonRect(width: 140, height: 14)
                        skeletonRect(width: 200, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s3)
            }
        }
    }

    // MARK: - Helpers

    private func skeletonRect(width: CGFloat? = nil, height: CGFloat = 14) -> some View {
        Capsule()
            .fill(Tide.fillStrong)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: Tide.s6) {
        LoadingStateView(style: .cards)
        LoadingStateView(style: .list)
    }
    .padding(Tide.edge)
    .tidePage()
}
