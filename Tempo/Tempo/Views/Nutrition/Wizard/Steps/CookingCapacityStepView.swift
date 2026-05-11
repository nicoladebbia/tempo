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
                HStack(spacing: TempoSpacing.md) {
                    ForEach(0 ... 7, id: \.self) { day in
                        button(for: day)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

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

    private func button(for day: Int) -> some View {
        let selected = coordinator.intake.cookableDaysThisWeek == day
        return Button {
            HapticManager.selection()
            coordinator.intake.cookableDaysThisWeek = day
        } label: {
            Text("\(day)")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(selected ? Color.tempoTextInverse : Color.tempoTextPrimary)
                .frame(width: 36, height: 36)
                .background(selected ? Color.tempoSignal : Color.tempoSurfaceElevated)
                .clipShape(Circle())
        }
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
