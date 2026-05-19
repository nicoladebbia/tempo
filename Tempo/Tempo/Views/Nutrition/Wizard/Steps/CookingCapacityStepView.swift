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

    var body: some View {
        WizardStepScaffold(
            title: "Real cook count.",
            subtitle: "How many days this week can you actually cook? Not optimistic — real.",
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            onBack: coordinator.goBack,
            onPrimary: coordinator.advance,
            onCancel: coordinator.cancel
        ) {
            VStack(spacing: TempoSpacing.lg) {
                dayPicker

                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text(footerLabel)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TempoSpacing.sm)
            }
        }
    }

    private static let dayCount = 8
    private static let interButtonSpacing = TempoSpacing.sm
    private static let maxDiameter: CGFloat = 44

    private var dayPicker: some View {
        GeometryReader { geo in
            let totalSpacing = Self.interButtonSpacing * CGFloat(Self.dayCount - 1)
            let fitDiameter = (geo.size.width - totalSpacing) / CGFloat(Self.dayCount)
            let diameter = max(28, min(Self.maxDiameter, fitDiameter))
            HStack(spacing: Self.interButtonSpacing) {
                ForEach(0 ..< Self.dayCount, id: \.self) { day in
                    button(for: day, diameter: diameter)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: Self.maxDiameter)
    }

    private func button(for day: Int, diameter: CGFloat) -> some View {
        let selected = coordinator.intake.cookableDaysThisWeek == day
        return Button {
            HapticManager.selection()
            coordinator.intake.cookableDaysThisWeek = day
        } label: {
            Text("\(day)")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.6)
                .foregroundStyle(selected ? Color.tempoTextInverse : Color.tempoTextPrimary)
                .frame(width: diameter, height: diameter)
                .background(selected ? Color.tempoSignal : Color.tempoSurfaceElevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
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
