//
// MacrosWidget.swift
// TempoWidget
//
// "Macros": calories and protein, carbs and fat against today's targets, the
// same figures as the Fuel card on Today.
//

import SwiftUI
import WidgetKit

// MARK: - TempoMacrosWidget

struct TempoMacrosWidget: Widget {
    let kind = "TempoMacrosWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempoWidgetProvider()) { entry in
            MacrosWidgetView(entry: entry)
                .tideWidgetContainer(entry.mood)
        }
        .configurationDisplayName("Macros")
        .description("Calories, protein, carbs and fat against today's targets.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - MacrosWidgetView

struct MacrosWidgetView: View {
    @Environment(\.widgetFamily)
    private var family
    let entry: TempoWidgetEntry

    private struct Macro: Identifiable {
        let id: String
        let name: String
        let grams: Int?
        let target: Int?
        let color: Color

        var fraction: Double? {
            WidgetSnapshot.fraction(grams, of: target)
        }
    }

    private var snapshot: WidgetSnapshot? {
        entry.snapshot
    }

    /// Nothing eaten yet and no targets: the app has no Fuel numbers to show.
    private var hasFuel: Bool {
        guard let snapshot else {
            return false
        }
        return snapshot.calories != nil || snapshot.calorieTarget != nil
    }

    private var macros: [Macro] {
        [
            Macro(id: "protein", name: String(localized: "Protein"), grams: snapshot?.protein, target: snapshot?.proteinTarget, color: Tide.protein),
            Macro(id: "carbs", name: String(localized: "Carbs"), grams: snapshot?.carbs, target: snapshot?.carbsTarget, color: Tide.carbs),
            Macro(id: "fat", name: String(localized: "Fat"), grams: snapshot?.fat, target: snapshot?.fatTarget, color: Tide.fat),
        ]
    }

    private var caloriesFraction: Double? {
        WidgetSnapshot.fraction(snapshot?.calories, of: snapshot?.calorieTarget)
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

    private var empty: some View {
        WidgetEmptyState(symbol: "fork.knife", title: String(localized: "No meals yet"), hint: String(localized: "Log a meal and your macros appear here."))
            .padding(Tide.s4)
    }

    private func macroRow(_ macro: Macro) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            HStack(alignment: .firstTextBaseline) {
                WidgetLabel(macro.name, color: macro.color)
                Spacer(minLength: Tide.s1)
                Text(macro.target.map { "\(WidgetSnapshot.text(macro.grams)) / \($0) g" } ?? "\(WidgetSnapshot.text(macro.grams)) g")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            WidgetBar(progress: macro.fraction, color: macro.color, height: Tide.barSlim)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Home screen

    @ViewBuilder
    private var small: some View {
        if hasFuel {
            VStack(alignment: .leading, spacing: Tide.s2) {
                WidgetLabel(String(localized: "Calories"))
                WidgetFigure(
                    value: WidgetSnapshot.text(snapshot?.calories),
                    unit: snapshot?.calorieTarget.map { "/ \($0.formatted())" } ?? "kcal",
                    size: Tide.numeralM
                )
                WidgetBar(progress: caloriesFraction, color: entry.mood.accent)
                Spacer(minLength: 0)
                ForEach(macros) { macro in
                    macroRow(macro)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(Tide.s4)
        } else {
            empty
        }
    }

    @ViewBuilder
    private var medium: some View {
        if hasFuel {
            HStack(spacing: Tide.s5) {
                ZStack {
                    WidgetRing(progress: caloriesFraction, color: entry.mood.accent, lineWidth: Tide.s2)
                    VStack(spacing: 0) {
                        WidgetFigure(value: WidgetSnapshot.text(snapshot?.calories), size: Tide.numeralS * 1.3)
                        Text(snapshot?.calorieTarget.map { String(localized: "of \($0.formatted()) kcal") } ?? "kcal")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, Tide.s3)
                }
                .aspectRatio(1, contentMode: .fit)
                VStack(spacing: Tide.s3) {
                    ForEach(macros) { macro in
                        macroRow(macro)
                    }
                }
            }
            .padding(Tide.s4)
        } else {
            empty
        }
    }

    // MARK: Lock screen

    private var circular: some View {
        Gauge(value: caloriesFraction ?? 0) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            Text(caloriesFraction.map { "\(Int(($0 * 100).rounded()))" } ?? "--")
                .font(Tide.numeral(Tide.numeralS))
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("Calories")
        .accessibilityValue(
            snapshot?.calorieTarget.map { String(localized: "\(WidgetSnapshot.text(snapshot?.calories)) of \($0) kilocalories") } ?? String(localized: "No target yet")
        )
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Label {
                Text(snapshot?.calorieTarget
                    .map { String(localized: "\(WidgetSnapshot.text(snapshot?.calories)) of \($0.formatted()) kcal") } ?? String(localized: "No meals yet"))
            } icon: {
                Image(systemName: "fork.knife")
            }
            .font(Tide.bodyStrong)
            .widgetAccentable()
            Gauge(value: caloriesFraction ?? 0) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
            Text(
                "P \(WidgetSnapshot.text(snapshot?.protein)) · C \(WidgetSnapshot.text(snapshot?.carbs)) · F \(WidgetSnapshot.text(snapshot?.fat)) g"
            )
            .font(Tide.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var inline: some View {
        Label(
            snapshot?.calories.map { String(localized: "\($0.formatted()) kcal · P \(WidgetSnapshot.text(snapshot?.protein)) g") } ?? String(localized: "No meals yet"),
            systemImage: "fork.knife"
        )
    }
}
