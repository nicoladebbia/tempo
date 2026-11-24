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

    /// True when pushed on another stack (Today): no stack of its own, or the
    /// nested stack would pop back to the root on every push.
    var embedded = false

    var body: some View {
        EmbeddableNavigationStack(embedded: embedded) {
            LockdownMainView(viewModel: viewModel, showFocusTimer: $showFocusTimer)
                .navigationTitle("Lockdown")
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
                                .font(Tide.headline)
                                .foregroundStyle(Tide.text2)
                                .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("More options")
                    }
                }
                // The home's shaders rest while the timer or the setup sheet covers it.
                .tideCovered(showFocusTimer || showSetup)
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
                // A non-negotiable completed elsewhere (e.g. from the watch).
                .onReceive(NotificationCenter.default.publisher(for: .tempoNonNegotiableChanged)) { _ in
                    viewModel.loadToday(modelContext: modelContext)
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
    @Environment(\.tideMood)
    private var mood

    @State
    private var showOverrideConfirmation = false
    @State
    private var pendingOverride: AccountabilityOverrideType?

    var body: some View {
        TideScrollPage {
            TideSectionLabel(title: "Override type")

            // Six choices read as one list, not six cards.
            VStack(spacing: 0) {
                ForEach(Array(overrideOptions.enumerated()), id: \.element.type) { index, option in
                    if index > 0 {
                        TideDivider()
                    }
                    optionRow(option)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

            Text("Overrides modify today's non-negotiable targets. Use sparingly — rest days don't count toward your streak.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.activeOverride != nil {
                Button {
                    viewModel.deactivateOverride()
                } label: {
                    Text("Cancel override")
                        .foregroundStyle(Tide.danger)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
            }
        }
        .navigationTitle("Override")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Activate Override", isPresented: $showOverrideConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingOverride = nil
            }
            Button("Activate") {
                if let type = pendingOverride {
                    withAnimation(Tide.snap) {
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

    private func optionRow(_ option: OverrideOption) -> some View {
        let isActive = viewModel.activeOverride == option.type
        return Button {
            pendingOverride = option.type
            showOverrideConfirmation = true
        } label: {
            HStack(spacing: Tide.s3) {
                TideAreaIconTile(systemName: option.icon, tint: isActive ? TideTone.mint : mood.accent)

                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(option.title)
                        .font(Tide.headline)
                        .foregroundStyle(isActive ? TideTone.mint : Tide.text)

                    Text(option.description)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Tide.s2)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Tide.title2)
                        .foregroundStyle(TideTone.mint)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Tide.s3)
            .frame(minHeight: Tide.hit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isActive)
        .accessibilityLabel("\(option.title)\(isActive ? ", active" : "")")
        .accessibilityHint(option.description)
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
