//
// LockdownTabView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - LockdownTabView

// Per BUILD_PLAN step 10.8.
// Per MODULE_ACCOUNTABILITY.md — Tab container with navigation.

struct LockdownTabView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]

    @State
    private var viewModel = AccountabilityViewModel()
    @State
    private var showFocusTimer = false
    @State
    private var showSetup = false
    @State
    private var hasAppeared = false

    private var settings: UserSettings? {
        allSettings.first
    }

    private var focusTimerEnabled: Bool {
        settings?.focusTimerEnabled ?? false
    }

    var body: some View {
        NavigationStack {
            LockdownMainView(viewModel: viewModel, showFocusTimer: $showFocusTimer)
                .navigationTitle("LOCKDOWN")
                .navigationBarTitleDisplayMode(.inline)
                .tempoSettingsToolbar()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            NavigationLink {
                                StreakCalendarView(viewModel: viewModel)
                            } label: {
                                Label("Streak Calendar", systemImage: "flame.fill")
                            }

                            NavigationLink {
                                WeeklyAccountabilityView()
                            } label: {
                                Label("Weekly Report Card", systemImage: "doc.text.fill")
                            }

                            Button {
                                showSetup = true
                            } label: {
                                Label("Edit Non-Neg.", systemImage: "list.bullet")
                            }

                            if focusTimerEnabled {
                                NavigationLink {
                                    FocusHistoryView()
                                } label: {
                                    Label("Focus History", systemImage: "chart.bar.fill")
                                }
                            }

                            NavigationLink {
                                overrideView
                            } label: {
                                Label("Rest Day / Override", systemImage: "bed.double.fill")
                            }

                            Divider()

                            Toggle(isOn: Binding(
                                get: { focusTimerEnabled },
                                set: { newValue in
                                    settings?.focusTimerEnabled = newValue
                                }
                            )) {
                                Label("Focus Timer", systemImage: "timer")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                }
                .fullScreenCover(isPresented: $showFocusTimer) {
                    if focusTimerEnabled {
                        FocusTimerView(viewModel: viewModel)
                    }
                }
                .sheet(isPresented: $showSetup) {
                    NonNegotiableSetupView()
                        .onDisappear {
                            // Reload after editing non-negotiables
                            viewModel.loadToday(modelContext: modelContext)
                        }
                }
                .task {
                    guard !hasAppeared else {
                        return
                    }
                    viewModel.loadToday(modelContext: modelContext)
                    hasAppeared = true
                }
        }
    }

    // MARK: - Override View

    // Per MODULE_ACCOUNTABILITY.md Section 13.

    private var overrideView: some View {
        OverrideSelectionView(viewModel: viewModel)
    }
}

// MARK: - OverrideSelectionView

// Extracted as a standalone View struct so @Observable tracking works
// correctly when pushed as a NavigationLink destination.

private struct OverrideSelectionView: View {
    @Bindable
    var viewModel: AccountabilityViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var showOverrideConfirmation = false
    @State
    private var pendingOverride: AccountabilityOverrideType?

    var body: some View {
        List {
            Section {
                ForEach(overrideOptions, id: \.type) { option in
                    let isActive = viewModel.activeOverride == option.type

                    Button {
                        pendingOverride = option.type
                        showOverrideConfirmation = true
                    } label: {
                        HStack(spacing: TempoSpacing.md) {
                            Image(systemName: option.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(isActive ? Color.tempoSuccess : Color.tempoElectric)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                                Text(option.title)
                                    .font(.tempoHeadline)
                                    .foregroundStyle(isActive ? Color.tempoSuccess : Color.tempoTextPrimary)

                                Text(option.description)
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            }

                            Spacer()

                            if isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.tempoSuccess)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .disabled(isActive)
                }
            } header: {
                Text("OVERRIDE TYPE")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            } footer: {
                Text("Overrides modify today's non-negotiable targets. Use sparingly — rest days don't count toward your streak.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .listRowBackground(Color.tempoSurfaceCard)

            if viewModel.activeOverride != nil {
                Section {
                    Button(role: .destructive) {
                        viewModel.deactivateOverride()
                    } label: {
                        Text("Cancel Override")
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoSignal)
                    }
                }
                .listRowBackground(Color.tempoSurfaceCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Override")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Activate Override", isPresented: $showOverrideConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingOverride = nil
            }
            Button("Activate") {
                if let type = pendingOverride {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.activateOverride(
                            type: type,
                            modelContext: modelContext
                        )
                    }
                    HapticManager.notification(.success)
                    pendingOverride = nil
                }
            }
        } message: {
            if let type = pendingOverride,
               let option = overrideOptions.first(where: { $0.type == type })
            {
                Text("\(option.title): \(option.description). This cannot be undone for today.")
            }
        }
    }

    private struct OverrideOption {
        let type: AccountabilityOverrideType
        let icon: String
        let title: String
        let description: String
    }

    private var overrideOptions: [OverrideOption] {
        [
            OverrideOption(
                type: .restDayFull,
                icon: "bed.double.fill",
                title: "Full Rest Day",
                description: "All non-negotiables suspended"
            ),
            OverrideOption(
                type: .restDayReduced,
                icon: "leaf.fill",
                title: "Reduced Rest Day",
                description: "Training skipped, study halved, meals remain"
            ),
            OverrideOption(
                type: .sickDay,
                icon: "cross.case.fill",
                title: "Sick Day",
                description: "Training skipped, study/meals reduced"
            ),
            OverrideOption(
                type: .mentalHealthDay,
                icon: "brain.head.profile",
                title: "Mental Health Day",
                description: "Study & training reduced, meals at full"
            ),
            OverrideOption(
                type: .injuryMode,
                icon: "bandage.fill",
                title: "Injury Mode",
                description: "Training auto-skipped, everything else full"
            ),
            OverrideOption(
                type: .vacationMode,
                icon: "airplane",
                title: "Vacation Mode",
                description: "All suspended"
            ),
        ]
    }
}
