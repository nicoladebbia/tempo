//
// NextWidget.swift
// TempoWidget
//
// "Next up": the one thing to do now, the same choice and the same words as
// the Today hero. Tapping it opens the tab that owns it.
//

import SwiftUI
import WidgetKit

// MARK: - TempoNextWidget

struct TempoNextWidget: Widget {
    let kind = "TempoNextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempoWidgetProvider()) { entry in
            NextWidgetView(entry: entry)
                .tideWidgetContainer(entry.mood)
        }
        .configurationDisplayName("Next up")
        .description("The one thing to do now: your session, your next meal or your next task.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

extension WidgetSnapshot.Next.Kind {
    var symbol: String {
        switch self {
        case .workout: "dumbbell.fill"
        case .meal,
             .firstMeal: "fork.knife"
        case .rest: "heart.fill"
        case .focus: "timer"
        case .tasks: "checklist"
        case .setUpTasks: "plus"
        case .allDone: "checkmark.circle.fill"
        }
    }
}

// MARK: - NextWidgetView

struct NextWidgetView: View {
    @Environment(\.widgetFamily)
    private var family
    let entry: TempoWidgetEntry

    private var next: WidgetSnapshot.Next? {
        entry.snapshot?.next
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
        .widgetURL((next?.destination ?? .today).url)
    }

    private var empty: some View {
        WidgetEmptyState(symbol: "arrow.forward.circle.fill", title: "Nothing queued yet")
            .padding(Tide.s4)
    }

    private func icon(_ next: WidgetSnapshot.Next, size: CGFloat) -> some View {
        Image(systemName: next.kind.symbol)
            .font(.tideGlyph(size * WidgetMetrics.glyphShare))
            .foregroundStyle(entry.mood.accent)
            .frame(width: size, height: size)
            .background(entry.mood.accent.opacity(0.16), in: .rect(cornerRadius: size * WidgetMetrics.tileCorner, style: .continuous))
            .widgetAccentable()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var small: some View {
        if let next {
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack {
                    icon(next, size: Tide.s8)
                    Spacer(minLength: Tide.s1)
                    if let trailing = next.trailing {
                        Text(trailing)
                            .font(Tide.numeral(Tide.numeralS))
                            .foregroundStyle(Tide.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                WidgetLabel("Next up")
                Text(next.title)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(Tide.s4)
        } else {
            empty
        }
    }

    @ViewBuilder
    private var medium: some View {
        if let next {
            HStack(alignment: .top, spacing: Tide.s4) {
                icon(next, size: Tide.s10 + Tide.s2)
                VStack(alignment: .leading, spacing: Tide.s2) {
                    HStack(alignment: .firstTextBaseline) {
                        WidgetLabel("Next up")
                        Spacer(minLength: Tide.s2)
                        if let trailing = next.trailing {
                            Text(trailing)
                                .font(Tide.numeral(Tide.numeralS))
                                .foregroundStyle(Tide.text)
                        }
                    }
                    Text(next.title)
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(next.detail)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(Tide.s4)
        } else {
            empty
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let next {
            VStack(alignment: .leading, spacing: Tide.hair) {
                Label {
                    Text("Next up")
                } icon: {
                    Image(systemName: next.kind.symbol)
                }
                .font(Tide.label)
                .widgetAccentable()
                Text(next.trailing.map { "\(next.title) · \($0)" } ?? next.title)
                    .font(Tide.bodyStrong)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            Text("Next up: open Tempo to set up your day")
                .font(Tide.caption)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let next {
            Label(next.trailing.map { "\(next.title) \($0)" } ?? next.title, systemImage: next.kind.symbol)
        } else {
            Text("Next up: nothing yet")
        }
    }
}
