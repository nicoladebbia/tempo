//
// RecoveryTabView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - RecoveryTabView

// Per MODULE_RECOVERY.md Section 2. One page, one question (how recovered am I
// and why), with a Day / Week / Month switch: Day is today's score, vitals,
// sleep and strain; Week and Month are the trends. They used to be four tabs.

struct RecoveryTabView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @State
    private var viewModel: RecoveryViewModel?

    /// True when pushed on another stack (Today): no stack of its own, or the
    /// nested stack would pop back to the root on every push.
    var embedded = false

    var body: some View {
        EmbeddableNavigationStack(embedded: embedded) {
            Group {
                if let viewModel {
                    recoveryContent(viewModel: viewModel)
                } else {
                    RecoverySkeleton()
                        .tidePage(energy: 1)
                }
            }
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .tempoSettingsToolbar()
        }
        .onAppear {
            if viewModel == nil {
                viewModel = RecoveryViewModel(
                    whoop: services.whoop,
                    recoveryEngine: services.recoveryEngine,
                    calendar: services.calendar
                )
            }
        }
    }

    // MARK: - Recovery Content

    private func recoveryContent(viewModel: RecoveryViewModel) -> some View {
        @Bindable
        var vm = viewModel
        return VStack(spacing: Tide.s2) {
            VStack(spacing: Tide.s2) {
                TidePillPicker(
                    options: RecoveryRange.allCases,
                    selection: $vm.selectedRange,
                    title: \.rawValue,
                    label: "Recovery period"
                )

                // A month can reach back 30 or 90 days.
                if viewModel.selectedRange == .month {
                    TidePillPicker(
                        options: MonthSpan.allCases,
                        selection: Binding(
                            get: { vm.monthShowsQuarter ? .ninety : .thirty },
                            set: { vm.monthShowsQuarter = $0 == .ninety }
                        ),
                        title: \.rawValue,
                        label: "Month length"
                    )
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)

            Group {
                switch viewModel.selectedRange {
                case .day:
                    RecoveryDayView(viewModel: viewModel)
                case .week,
                     .month:
                    RecoveryPeriodView(viewModel: viewModel)
                }
            }
            .transition(.opacity)
        }
        .animation(Tide.snap, value: viewModel.selectedRange)
        .tidePage(energy: 1)
        // One load for the whole page, whichever view is showing.
        .task {
            if viewModel.loadState != .loaded {
                await viewModel.refresh(modelContext: modelContext)
            }
        }
    }
}

// MARK: - MonthSpan

/// How far back the Month view reaches.
private enum MonthSpan: String, CaseIterable {
    case thirty = "30 days"
    case ninety = "90 days"
}
