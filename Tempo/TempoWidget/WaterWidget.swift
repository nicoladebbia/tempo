//
// WaterWidget.swift
// TempoWidget
//
// "Water": today's total against the day's target, with a +250 ml button that
// logs a glass without opening the app (`LogWaterIntent`, the same store and
// Apple Health write as every other water log).
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - TempoWaterWidget

struct TempoWaterWidget: Widget {
    let kind = "TempoWaterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempoWidgetProvider()) { entry in
            WaterWidgetView(entry: entry)
                .tideWidgetContainer(entry.mood)
        }
        .configurationDisplayName("Water")
        .description("Today's water, and a button to add a glass.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - WaterWidgetView

struct WaterWidgetView: View {
    /// The glass the button adds.
    static let glassMl = 250

    @Environment(\.widgetFamily)
    private var family
    let entry: TempoWidgetEntry

    private var snapshot: WidgetSnapshot? {
        entry.snapshot
    }

    private var total: Int {
        snapshot?.waterMl ?? 0
    }

    private var target: Int? {
        snapshot?.waterTargetMl
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
        .widgetURL(WidgetDestination.fuel.url)
    }

    private var addButton: some View {
        Button(intent: LogWaterIntent(amountMl: Self.glassMl)) {
            Label("+\(Self.glassMl) ml", systemImage: "drop.fill")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.ink)
                .frame(maxWidth: .infinity, minHeight: Tide.hit)
                .background(Tide.water, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(Self.glassMl) millilitres of water")
    }

    private var ring: some View {
        ZStack {
            WidgetRing(progress: snapshot?.waterFraction, color: Tide.water, lineWidth: Tide.s2)
            VStack(spacing: 0) {
                WidgetFigure(value: total.formatted(), size: Tide.numeralS * 1.3)
                Text("ml")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text2)
            }
            .padding(.horizontal, Tide.s3)
        }
    }

    // MARK: Home screen

    @ViewBuilder
    private var small: some View {
        if snapshot == nil {
            // The button still works: logging creates today's numbers.
            VStack(spacing: Tide.s2) {
                WidgetEmptyState(symbol: "drop.fill", title: "No water yet", hint: "Add a glass.", compact: true)
                addButton
            }
            .padding(Tide.s3)
        } else {
            VStack(spacing: Tide.s2) {
                ring
                    .frame(maxWidth: .infinity)
                    .padding(.top, Tide.s1)
                addButton
            }
            .padding(Tide.s3)
        }
    }

    private var medium: some View {
        HStack(spacing: Tide.s5) {
            ring
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: Tide.s2) {
                WidgetLabel("Water today")
                if let target {
                    WidgetFigure(value: total.formatted(), unit: "of \(target.formatted()) ml", size: Tide.numeralM)
                    WidgetBar(progress: snapshot?.waterFraction, color: Tide.water)
                } else {
                    WidgetFigure(value: total.formatted(), unit: "ml", size: Tide.numeralM)
                    Text("Open Tempo to set today's target.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                Spacer(minLength: 0)
                addButton
            }
        }
        .padding(Tide.s4)
    }

    // MARK: Lock screen

    private var circular: some View {
        Gauge(value: snapshot?.waterFraction ?? 0, in: 0 ... 1) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text(snapshot?.waterFraction.map { "\(Int(($0 * 100).rounded()))" } ?? "--")
                .font(Tide.numeral(Tide.numeralS))
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("Water")
        .accessibilityValue(target.map { "\(total) of \($0) millilitres" } ?? "\(total) millilitres")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Label {
                Text(target.map { "\(total.formatted()) of \($0.formatted()) ml" } ?? "\(total.formatted()) ml")
            } icon: {
                Image(systemName: "drop.fill")
            }
            .font(Tide.bodyStrong)
            .widgetAccentable()
            Gauge(value: snapshot?.waterFraction ?? 0, in: 0 ... 1) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Button(intent: LogWaterIntent(amountMl: Self.glassMl)) {
                Text("+\(Self.glassMl) ml")
                    .font(Tide.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label(
            target.map { "Water \(total.formatted()) of \($0.formatted()) ml" } ?? "Water \(total.formatted()) ml",
            systemImage: "drop.fill"
        )
    }
}
