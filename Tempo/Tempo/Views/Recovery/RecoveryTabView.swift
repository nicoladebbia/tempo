//
// RecoveryTabView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Recovery Tab View

// Per MODULE_RECOVERY.md Section 2 — Tab container with segmented control.
// Per BUILD_PLAN.md Step 8.6 — Today / Sleep / Strain / Trends tabs + gear icon.

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
            // Per MODULE_RECOVERY.md Section 2 — Today / Sleep / Strain / Trends
            TidePillPicker(
                options: RecoveryTab.allCases,
                selection: $vm.selectedTab,
                title: \.rawValue,
                label: "Recovery section"
            )
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)

            // Tab content
            Group {
                switch viewModel.selectedTab {
                case .today:
                    RecoveryTodayView(viewModel: viewModel)
                case .sleep:
                    SleepDetailView(viewModel: viewModel)
                case .strain:
                    StrainDetailView(viewModel: viewModel)
                case .trends:
                    RecoveryTrendsView(viewModel: viewModel)
                }
            }
            .transition(.opacity)
        }
        .animation(Tide.snap, value: viewModel.selectedTab)
        .tidePage(energy: 1)
    }
}
