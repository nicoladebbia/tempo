//
// Tide+Coach.swift
// Tempo
//
// Pieces the Coach screens share: chat bubbles, the calm loading shimmer,
// choice chips and rows, glass text fields and the round icon button.
// Every type here is prefixed `TideCoach` so it cannot collide with the
// helpers other areas add.
//

import SwiftUI

// MARK: - TideCoach

enum TideCoach {
    /// Radius of a chat bubble: the same as a tile.
    static let bubbleRadius: CGFloat = Tide.tileRadius
    /// The corner next to the speaker is nearly square, like a tail.
    static let bubbleTail: CGFloat = Tide.s1
    /// Space kept free beside a bubble so long messages wrap before the far edge.
    static let bubbleGutter: CGFloat = Tide.s10
    /// A figure inside a row or a chip: between the label and tile sizes.
    static let figureSmall: CGFloat = 15
    /// Height of a one-line text field. Multi-line fields grow past it.
    static let fieldHeight: CGFloat = Tide.hit
}

// MARK: - TideCoachBubbleRole

enum TideCoachBubbleRole {
    /// The person typing: filled with the mood accent, ink text.
    case user
    /// Coach: a tinted glass card.
    case assistant
}

// MARK: - TideCoachBubbleModifier

private struct TideCoachBubbleModifier: ViewModifier {
    let role: TideCoachBubbleRole

    @Environment(\.tideMood)
    private var mood

    private var shape: UnevenRoundedRectangle {
        let r = TideCoach.bubbleRadius, tail = TideCoach.bubbleTail
        return switch role {
        case .user:
            UnevenRoundedRectangle(
                topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: tail, topTrailingRadius: r,
                style: .continuous
            )
        case .assistant:
            UnevenRoundedRectangle(
                topLeadingRadius: r, bottomLeadingRadius: tail, bottomTrailingRadius: r, topTrailingRadius: r,
                style: .continuous
            )
        }
    }

    func body(content: Content) -> some View {
        switch role {
        case .user:
            content
                .font(Tide.body)
                .foregroundStyle(Tide.ink)
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s3)
                .background(mood.accent, in: shape)
        case .assistant:
            content
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s3)
                .glassEffect(.regular.tint(Tide.glassCard), in: shape)
        }
    }
}

extension View {
    /// Wraps a message in a bubble: accent fill for the user, glass for Coach.
    func tideCoachBubble(_ role: TideCoachBubbleRole) -> some View {
        modifier(TideCoachBubbleModifier(role: role))
    }

    /// A slow band of light that passes over this view while it loads.
    /// Under Reduce Motion it is a still, slightly dimmed view.
    func tideCoachShimmer() -> some View {
        modifier(TideCoachShimmer())
    }

    /// The look of a text field: a glass plate with room to type.
    func tideCoachField() -> some View {
        modifier(TideCoachFieldModifier())
    }
}

// MARK: - TideCoachShimmer

private struct TideCoachShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.7)
        } else {
            content
                .mask {
                    LinearGradient(
                        colors: [.black.opacity(0.45), .black, .black.opacity(0.45)],
                        startPoint: UnitPoint(x: phase, y: 0.5),
                        endPoint: UnitPoint(x: phase + 1, y: 0.5)
                    )
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

// MARK: - TideCoachSkeleton

/// Placeholder bubbles shown while Coach is getting ready.
struct TideCoachSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            bar(width: 0.62, alignment: .leading)
            bar(width: 0.46, alignment: .trailing)
            bar(width: 0.7, alignment: .leading)
        }
        .padding(.horizontal, Tide.edge)
        .tideCoachShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Coach")
    }

    private func bar(width: CGFloat, alignment: Alignment) -> some View {
        Color.clear
            .frame(height: Tide.hit + Tide.s2)
            .containerRelativeFrame(.horizontal) { length, _ in length * width }
            .background(Tide.fill, in: .rect(cornerRadius: TideCoach.bubbleRadius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

// MARK: - TideCoachFieldModifier

private struct TideCoachFieldModifier: ViewModifier {
    @Environment(\.tideMood)
    private var mood

    func body(content: Content) -> some View {
        content
            .font(Tide.body)
            .foregroundStyle(Tide.text)
            .tint(mood.accent)
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s3)
            .frame(minHeight: TideCoach.fieldHeight, alignment: .leading)
            .glassEffect(.regular.tint(Tide.glassControl), in: .rect(cornerRadius: Tide.controlRadius))
    }
}

// MARK: - TideCoachCircleButtonStyle

/// A 44 pt round glass button for one icon.
struct TideCoachCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.bodyStrong)
            .foregroundStyle(configuration.role == .destructive ? Tide.danger : Tide.text)
            .frame(width: Tide.hit, height: Tide.hit)
            .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.circle)
    }
}

extension ButtonStyle where Self == TideCoachCircleButtonStyle {
    static var tideCoachCircle: TideCoachCircleButtonStyle {
        TideCoachCircleButtonStyle()
    }
}

// MARK: - TideCoachPressStyle

/// Cards that open something dip slightly under the finger.
struct TideCoachPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tide.pressCard : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

// MARK: - TideCoachChoiceChips

/// A short row of exclusive choices (Likes / Dislikes / Hard avoids).
/// The chosen chip is filled with the accent; the others are glass. Chips go
/// one per line when the text size is too big for a single row.
struct TideCoachChoiceChips<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var count: Int?
    }

    let options: [Option]
    @Binding
    var selection: Value

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        GlassEffectContainer(spacing: Tide.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) { chips(fill: false) }
                VStack(spacing: Tide.s2) { chips(fill: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chips(fill: Bool) -> some View {
        ForEach(options.indices, id: \.self) { index in
            chip(options[index], fill: fill)
        }
    }

    @ViewBuilder
    private func chip(_ option: Option, fill: Bool) -> some View {
        let isSelected = option.value == selection
        Button {
            withAnimation(Tide.snap) { selection = option.value }
        } label: {
            HStack(spacing: Tide.s2) {
                Text(option.title).font(Tide.bodyStrong).lineLimit(1)
                if let count = option.count {
                    TideNumber(
                        "\(count)", size: TideCoach.figureSmall, relativeTo: .subheadline, weight: .semibold,
                        color: isSelected ? Tide.ink.opacity(0.72) : Tide.text2
                    )
                }
            }
            .foregroundStyle(isSelected ? Tide.ink : Tide.text)
            .padding(.horizontal, Tide.s3)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: Tide.hit)
            .background {
                if isSelected {
                    Capsule().fill(mood.accent)
                }
            }
            .glassEffect(isSelected ? .identity : .regular.tint(Tide.glassControl).interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - TideCoachOptionRow

/// One answer in a question: a glass row with a round or square tick.
struct TideCoachOptionRow: View {
    enum Mark {
        /// Pick one.
        case radio
        /// Pick any.
        case check
    }

    let label: String
    let isSelected: Bool
    var mark: Mark = .radio
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood

    private var symbol: String {
        switch (mark, isSelected) {
        case (.radio, true): "checkmark.circle.fill"
        case (.radio, false): "circle"
        case (.check, true): "checkmark.square.fill"
        case (.check, false): "square"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tide.s3) {
                Image(systemName: symbol)
                    .font(Tide.title2)
                    .foregroundStyle(isSelected ? mood.accent : Tide.text3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Tide.icon)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s3)
            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s2, alignment: .leading)
            .glassEffect(
                .regular.tint(isSelected ? mood.accent.opacity(0.3) : Tide.glassCard).interactive(),
                in: .rect(cornerRadius: Tide.tileRadius)
            )
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(.plain)
        .animation(Tide.snap, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - TideCoachPill

/// A tiny tinted tag ("Review", "Verified").
struct TideCoachPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .tideLabel(color)
            .lineLimit(1)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.s1)
            .background(color.opacity(0.16), in: .capsule)
    }
}
