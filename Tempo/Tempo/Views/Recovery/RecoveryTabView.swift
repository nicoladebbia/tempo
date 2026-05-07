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

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    recoveryContent(viewModel: viewModel)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.tempoBgPrimary)
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
        return VStack(spacing: 0) {
            // Segmented control
            // Per MODULE_RECOVERY.md Section 2 — Today / Sleep / Strain / Trends
            Picker("Recovery Section", selection: $vm.selectedTab) {
                ForEach(RecoveryTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.sm)

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
        }
        .background(Color.tempoBgPrimary)
    }
}
