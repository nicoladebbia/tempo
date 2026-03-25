import SwiftUI

// MARK: - Loading State View
// Per DESIGN_SYSTEM.md Section 11 — Skeleton loading with shimmer animation.

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

    var body: some View {
        Group {
            switch style {
            case .cards:
                cardSkeletons
            case .quadrants:
                quadrantSkeletons
            case .list:
                listSkeletons
            }
        }
        .shimmer()
    }

    // MARK: - Card Skeletons

    private var cardSkeletons: some View {
        VStack(spacing: TempoSpacing.cardGap) {
            ForEach(0..<style.itemCount, id: \.self) { _ in
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    skeletonRect(width: 120, height: 12)
                    skeletonRect(height: 20)
                    skeletonRect(width: 200, height: 12)
                }
                .tempoCard()
            }
        }
    }

    // MARK: - Quadrant Skeletons

    private var quadrantSkeletons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TempoSpacing.cardGap) {
            ForEach(0..<style.itemCount, id: \.self) { _ in
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    skeletonRect(width: 80, height: 12)
                    Spacer()
                    skeletonRect(width: 60, height: 24)
                    skeletonRect(width: 100, height: 10)
                }
                .padding(TempoSpacing.cardPaddingCompact)
                .aspectRatio(1, contentMode: .fit)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            }
        }
    }

    // MARK: - List Skeletons

    private var listSkeletons: some View {
        VStack(spacing: 0) {
            ForEach(0..<style.itemCount, id: \.self) { _ in
                HStack(spacing: TempoSpacing.md) {
                    Circle()
                        .fill(Color.tempoTextDisabled.opacity(0.3))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                        skeletonRect(width: 140, height: 14)
                        skeletonRect(width: 200, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, TempoSpacing.lg)
                .padding(.vertical, TempoSpacing.listItemVertical)
            }
        }
    }

    // MARK: - Helpers

    private func skeletonRect(width: CGFloat? = nil, height: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: TempoRadius.sm)
            .fill(Color.tempoTextDisabled.opacity(0.3))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
