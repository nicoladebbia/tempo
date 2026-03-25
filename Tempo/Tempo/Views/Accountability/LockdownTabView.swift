import SwiftUI
import SwiftData

// MARK: - Lockdown Tab Container
// Per BUILD_PLAN step 10.8.
// Per MODULE_ACCOUNTABILITY.md — Tab container with navigation.

struct LockdownTabView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = AccountabilityViewModel()
    @State private var showFocusTimer = false
    @State private var showSetup = false
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            LockdownMainView(viewModel: viewModel)
                .navigationTitle("LOCKDOWN")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            NavigationLink {
                                StreakCalendarView(viewModel: viewModel)
                            } label: {
                                Label("Streak Calendar", systemImage: "flame.fill")
                            }

                            Button {
                                showSetup = true
                            } label: {
                                Label("Edit Non-Negotiables", systemImage: "list.bullet")
                            }

                            NavigationLink {
                                overrideView
                            } label: {
                                Label("Rest Day / Override", systemImage: "bed.double.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                }
                .fullScreenCover(isPresented: $showFocusTimer) {
                    FocusTimerView(viewModel: viewModel)
                }
                .sheet(isPresented: $showSetup) {
                    NonNegotiableSetupView()
                        .onDisappear {
                            // Reload after editing non-negotiables
                            viewModel.loadToday(modelContext: modelContext)
                        }
                }
                .task {
                    guard !hasAppeared else { return }
                    viewModel.loadToday(modelContext: modelContext)
                    hasAppeared = true
                }
        }
    }

    // MARK: - Override View
    // Per MODULE_ACCOUNTABILITY.md Section 13.

    private var overrideView: some View {
        List {
            Section {
                ForEach(overrideOptions, id: \.type) { option in
                    Button {
                        viewModel.activateOverride(
                            type: option.type,
                            modelContext: modelContext
                        )
                    } label: {
                        HStack(spacing: TempoSpacing.md) {
                            Image(systemName: option.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(Color.tempoElectric)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                                Text(option.title)
                                    .font(.tempoHeadline)
                                    .foregroundStyle(Color.tempoTextPrimary)

                                Text(option.description)
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            }
                        }
                    }
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
    }

    private struct OverrideOption {
        let type: AccountabilityOverrideType
        let icon: String
        let title: String
        let description: String
    }

    private var overrideOptions: [OverrideOption] {
        [
            OverrideOption(type: .restDayFull, icon: "bed.double.fill",
                           title: "Full Rest Day", description: "All non-negotiables suspended"),
            OverrideOption(type: .restDayReduced, icon: "leaf.fill",
                           title: "Reduced Rest Day", description: "Training skipped, study halved, meals remain"),
            OverrideOption(type: .sickDay, icon: "cross.case.fill",
                           title: "Sick Day", description: "Training skipped, study/meals reduced"),
            OverrideOption(type: .mentalHealthDay, icon: "brain.head.profile",
                           title: "Mental Health Day", description: "Study & training reduced, meals at full"),
            OverrideOption(type: .injuryMode, icon: "bandage.fill",
                           title: "Injury Mode", description: "Training auto-skipped, everything else full"),
            OverrideOption(type: .vacationMode, icon: "airplane",
                           title: "Vacation Mode", description: "All suspended"),
        ]
    }
}
