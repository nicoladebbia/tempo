//
// CookingCapacityStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct CookingCapacityStepView: View {
    @Bindable
    var coordinator: WizardCoordinator

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .title)
    private var numeralSize: CGFloat = Tide.numeralM

    var body: some View {
        WizardStepScaffold(
            title: "Real cook count.",
            subtitle: "How many days this week can you actually cook? Not optimistic — real.",
            eyebrow: coordinator.stepCaption,
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            onBack: coordinator.goBack,
            onPrimary: coordinator.advance,
            onCancel: coordinator.cancel
        ) {
            VStack(alignment: .leading, spacing: Tide.s5) {
                // The answer and what it means for the plan, as one object.
                VStack(alignment: .leading, spacing: Tide.s2) {
                    TideNumber(
                        "\(coordinator.intake.cookableDaysThisWeek)",
                        unit: coordinator.intake.cookableDaysThisWeek == 1 ? "day" : "days",
                        size: Tide.numeralL
                    )
                    .contentTransition(.numericText())
                    Text(footerLabel)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Tide.snap, value: coordinator.intake.cookableDaysThisWeek)
                .accessibilityElement(children: .combine)
                dayPicker
            }
        }
    }

    private static let dayCount = 8

    /// Eight tiles, 0 to 7 days: four to a row, each with its label so the number is never bare.
    private var dayPicker: some View {
        GlassEffectContainer(spacing: Tide.s1) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: Tide.s2)], spacing: Tide.s2) {
                ForEach(0 ..< Self.dayCount, id: \.self) { day in
                    tile(for: day)
                }
            }
        }
    }

    private func tile(for day: Int) -> some View {
        let selected = coordinator.intake.cookableDaysThisWeek == day
        let unit = day == 1 ? "day" : "days"
        return Button {
            HapticManager.selection()
            coordinator.intake.cookableDaysThisWeek = day
        } label: {
            VStack(spacing: Tide.hair) {
                Text("\(day)")
                    .font(Tide.numeral(numeralSize))
                    .foregroundStyle(selected ? Tide.ink : Tide.text)
                Text(unit)
                    .font(Tide.label)
                    .foregroundStyle(selected ? Tide.ink : Tide.text2)
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s4)
            .background(selected ? mood.accent : Color.clear, in: .rect(cornerRadius: Tide.tileRadius))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Tide.tileRadius))
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(.plain)
        .animation(Tide.snap, value: selected)
        .accessibilityLabel("\(day) \(unit)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footerLabel: String {
        switch coordinator.intake.cookableDaysThisWeek {
        case 0: "Zero cooking days. Plan will lean on no-cook foods + leftovers."
        case 1 ... 2: "Light cooking week. Batches and quick assemblies."
        case 3 ... 4: "Standard. Most plans land here."
        case 5 ... 6: "Heavy cook week. Variety will be high."
        case 7: "Cooking every day. Solid commitment."
        default: ""
        }
    }
}
