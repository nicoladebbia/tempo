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
    /// Width of a rule or an outline: one point.
    static let rule: CGFloat = 1
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

/// Placeholder bubbles shown while Coach is getting ready: the same shape as
/// the chat (Coach's mark beside its bubbles, yours on the right), so nothing
/// jumps when it loads.
struct TideCoachSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            bar(width: 0.62, alignment: .leading, showsMark: true)
            bar(width: 0.46, alignment: .trailing, showsMark: false)
            bar(width: 0.7, alignment: .leading, showsMark: true)
        }
        .padding(.horizontal, Tide.edge)
        .tideCoachShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Coach")
    }

    private func bar(width: CGFloat, alignment: Alignment, showsMark: Bool) -> some View {
        HStack(alignment: .top, spacing: Tide.s2) {
            if showsMark {
                Circle()
                    .fill(Tide.fill)
                    .frame(width: TideCoachAvatar.width, height: TideCoachAvatar.width)
            }
            Color.clear
                .frame(height: Tide.hit + Tide.s2)
                .containerRelativeFrame(.horizontal) { length, _ in length * width }
                .background(Tide.fill, in: .rect(cornerRadius: TideCoach.bubbleRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: alignment)
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

// MARK: - TideCoachAvatar

/// Coach's mark beside its messages: a small accent disc with a spark. Hidden
/// from VoiceOver; the bubble beside it already says who is speaking.
struct TideCoachAvatar: View {
    @Environment(\.tideMood)
    private var mood
    /// Width a row should keep free so bubbles with and without the mark line up.
    /// Fixed, not scaled with text: the mark is decoration, and a scaled mark
    /// would push the first bubble of a run out of line with the rest.
    static let width: CGFloat = Tide.s8
    private var size: CGFloat {
        Self.width
    }

    /// How far Coach's rows sit in from the left: the mark and its gap, or
    /// nothing at accessibility sizes where the mark column is dropped.
    static func inset(for typeSize: DynamicTypeSize) -> CGFloat {
        typeSize.isAccessibilitySize ? 0 : width + Tide.s2
    }

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(Tide.ink)
            .frame(width: size, height: size)
            .background(mood.accent, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - TideCoachTypingDots

/// Three dots that rise in turn: Coach is writing. Under Reduce Motion they
/// stay still.
struct TideCoachTypingDots: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var up = false

    var body: some View {
        HStack(spacing: Tide.s1) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(Tide.text2)
                    .frame(width: Tide.s2, height: Tide.s2)
                    .offset(y: up && !reduceMotion ? -Tide.s1 : 0)
                    .opacity(up || reduceMotion ? 1 : 0.5)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.15),
                        value: up
                    )
            }
        }
        .onAppear { up = true }
        .accessibilityHidden(true)
    }
}

// MARK: - TideCoachDaySeparator

/// "Today", "Yesterday" or a date, between two hairlines: where one day of a
/// transcript ends and the next begins.
struct TideCoachDaySeparator: View {
    let date: Date

    /// "Today", "Yesterday", or "Monday 24 Nov".
    static func title(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    var body: some View {
        HStack(spacing: Tide.s3) {
            line
            Text(Self.title(for: date))
                .tideLabel(Tide.text3)
                .lineLimit(1)
                .fixedSize()
            line
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.title(for: date)))
        .accessibilityAddTraits(.isHeader)
    }

    private var line: some View {
        Rectangle()
            .fill(Tide.hairline)
            .frame(height: TideCoach.rule)
            .accessibilityHidden(true)
    }
}

// MARK: - TideCoachReplyButtonStyle

/// A quick reply under a question: an outlined accent capsule, the way a
/// suggested answer reads in a chat.
struct TideCoachReplyButtonStyle: ButtonStyle {
    @Environment(\.tideMood)
    private var mood

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.bodyStrong)
            .foregroundStyle(mood.accent)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s2)
            .frame(minHeight: Tide.hit)
            .glassEffect(.regular.tint(mood.accent.opacity(0.14)).interactive(), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(mood.accent.opacity(0.5), lineWidth: TideCoach.rule)
            }
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == TideCoachReplyButtonStyle {
    static var tideCoachReply: TideCoachReplyButtonStyle {
        TideCoachReplyButtonStyle()
    }
}
