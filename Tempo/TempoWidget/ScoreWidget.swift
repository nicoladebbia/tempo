//
// ScoreWidget.swift
// TempoWidget
//
// "Day score": the Today dial, small and medium on the home screen, and a
// gauge, a line and an inline text on the lock screen. Same number and same
// mood word as the Today screen.
//

import SwiftUI
import WidgetKit

// MARK: - TempoScoreWidget

struct TempoScoreWidget: Widget {
    /// Kept from the first widget, so one already on a home screen carries on.
    let kind = "TempoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempoWidgetProvider()) { entry in
            ScoreWidgetView(entry: entry)
                .tideWidgetContainer(entry.mood)
        }
        .configurationDisplayName("Day score")
        .description("Your score for today, and what is left to do.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - ScoreWidgetView

struct ScoreWidgetView: View {
    @Environment(\.widgetFamily)
    private var family
    let entry: TempoWidgetEntry

    private var snapshot: WidgetSnapshot? {
        entry.snapshot
    }

    private var score: Int? {
        snapshot?.score
    }

    private var scoreText: String {
        score.map(String.init) ?? "--"
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
        .widgetURL(WidgetDestination.today.url)
    }

    // MARK: Home screen

    @ViewBuilder
    private var small: some View {
        if snapshot == nil {
            WidgetEmptyState(symbol: "sun.horizon.fill", title: String(localized: "No score yet"))
                .padding(Tide.s4)
        } else {
            VStack(alignment: .leading, spacing: Tide.s2) {
                WidgetLabel(String(localized: "Day score"))
                ZStack {
                    WidgetDial(progress: score.map { Double($0) / 100 }, accent: entry.mood.accent)
                    WidgetFigure(value: scoreText, size: Tide.numeralL)
                        .padding(.horizontal, Tide.s5)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                Text(entry.mood.word)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(entry.mood.accent)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity)
            }
            .padding(Tide.s4)
        }
    }

    @ViewBuilder
    private var medium: some View {
        if let snapshot {
            HStack(spacing: Tide.s5) {
                ZStack {
                    WidgetDial(progress: score.map { Double($0) / 100 }, accent: entry.mood.accent, tick: 6)
                    VStack(spacing: 0) {
                        WidgetFigure(value: scoreText, size: Tide.numeralL)
                        WidgetLabel(String(localized: "Day score"))
                    }
                    .padding(.horizontal, Tide.s6)
                }
                .aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: Tide.s3) {
                    Text(entry.mood.word)
                        .font(Tide.title2)
                        .foregroundStyle(entry.mood.accent)
                        .widgetAccentable()
                    VStack(spacing: Tide.s2) {
                        statRow(
                            String(localized: "Tasks"),
                            value: snapshot.tasksTotal > 0 ? String(localized: "\(snapshot.tasksDone) of \(snapshot.tasksTotal)") : "--",
                            progress: WidgetSnapshot.fraction(snapshot.tasksDone, of: snapshot.tasksTotal),
                            color: entry.mood.accent
                        )
                        statRow(
                            String(localized: "Fuel"),
                            value: snapshot.calories.map { String(localized: "\($0.formatted()) kcal") } ?? "--",
                            progress: WidgetSnapshot.fraction(snapshot.calories, of: snapshot.calorieTarget),
                            color: Tide.carbs
                        )
                        statRow(
                            String(localized: "Water"),
                            value: snapshot.waterTargetMl == nil && snapshot.waterMl == 0 ? "--" : String(localized: "\(snapshot.waterMl.formatted()) ml"),
                            progress: snapshot.waterFraction,
                            color: Tide.water
                        )
                    }
                }
            }
            .padding(Tide.s4)
        } else {
            WidgetEmptyState(symbol: "sun.horizon.fill", title: String(localized: "No score yet"))
                .padding(Tide.s4)
        }
    }

    private func statRow(_ label: String, value: String, progress: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            HStack(alignment: .firstTextBaseline) {
                WidgetLabel(label)
                Spacer(minLength: Tide.s1)
                Text(value)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            WidgetBar(progress: progress, color: color, height: Tide.barSlim)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Lock screen

    private var circular: some View {
        Gauge(value: Double(score ?? 0), in: 0 ... 100) {
            Text("Day")
        } currentValueLabel: {
            Text(scoreText)
                .font(Tide.numeral(Tide.numeralS))
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("Day score")
        .accessibilityValue(score.map { String(localized: "\($0) out of 100") } ?? String(localized: "No score yet"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(scoreText)
                    .font(Tide.numeral(Tide.numeralS))
                    .widgetAccentable()
                Text(score == nil ? String(localized: "No score yet") : entry.mood.word)
                    .font(Tide.bodyStrong)
            }
            Gauge(value: Double(score ?? 0), in: 0 ... 100) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            if let snapshot, snapshot.tasksTotal > 0 {
                Text("\(snapshot.tasksDone) of \(snapshot.tasksTotal) tasks done")
                    .font(Tide.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var inline: some View {
        if let score {
            Text("Day \(score) · \(entry.mood.word)")
        } else {
            Text("Day score: none yet")
        }
    }
}
