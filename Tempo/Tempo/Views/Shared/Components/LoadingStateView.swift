//
// LoadingStateView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Loading State View

// Skeletons drawn as the glass cards they stand in for: a label, a numeral and
// a bar, laid out like the real thing. They breathe in a slow wave from the
// first item to the last instead of sweeping. Reduce Motion holds them still.

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

    /// Seconds between one item starting to breathe and the next.
    private let ripple = 0.14

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
        .onAppear { dim = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    /// One item's slow fade, started a beat after the one before it.
    private func breathing(_ index: Int) -> some ViewModifier {
        Breathing(dim: dim, reduceMotion: reduceMotion, delay: Double(index) * ripple)
    }

    // MARK: - Card Skeletons

    private var cardSkeletons: some View {
        VStack(spacing: Tide.s3) {
            ForEach(0 ..< style.itemCount, id: \.self) { index in
                VStack(alignment: .leading, spacing: Tide.s3) {
                    HStack {
                        skeletonRect(width: 96, height: 10)
                        Spacer(minLength: Tide.s4)
                        skeletonRect(width: 44, height: 10)
                    }
                    skeletonRect(width: 120, height: Tide.numeralM)
                    skeletonRect(height: Tide.bar)
                    skeletonRect(width: 200, height: 12)
                }
                .tideCard()
                .modifier(breathing(index))
            }
        }
    }

    // MARK: - Quadrant Skeletons

    private var quadrantSkeletons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Tide.s3) {
            ForEach(0 ..< style.itemCount, id: \.self) { index in
                VStack(alignment: .leading, spacing: Tide.s2) {
                    skeletonRect(width: 72, height: 10)
                    Spacer()
                    skeletonRect(width: 60, height: Tide.numeralS)
                    skeletonRect(height: Tide.barSlim)
                    skeletonRect(width: 100, height: 10)
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                .aspectRatio(1, contentMode: .fit)
                .modifier(breathing(index))
            }
        }
    }

    // MARK: - List Skeletons

    private var listSkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< style.itemCount, id: \.self) { index in
                HStack(spacing: Tide.s3) {
                    RoundedRectangle(cornerRadius: Tide.tile * 0.32, style: .continuous)
                        .fill(Tide.fillStrong)
                        .frame(width: Tide.tile, height: Tide.tile)
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        skeletonRect(width: 140, height: 14)
                        skeletonRect(width: 200, height: 10)
                    }
                    Spacer()
                    skeletonRect(width: 36, height: 12)
                }
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s3)
                .modifier(breathing(index))
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

    private struct Breathing: ViewModifier {
        let dim: Bool
        let reduceMotion: Bool
        let delay: Double

        func body(content: Content) -> some View {
            content
                .opacity(dim ? 0.5 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(delay),
                    value: dim
                )
        }
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
