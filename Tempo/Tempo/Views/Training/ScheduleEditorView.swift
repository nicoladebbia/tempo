//
// ScheduleEditorView.swift
// Tempo
//
// Tier 3 — edit the weekly schedule INPUTS (football/soccer days + training
// split) from the Week view. Writes UserSettings (what the generator reads) and
// mirrors to UserProfile (sync DTO parity), then posts
// `.tempoTrainingSettingsChanged` so the training week re-personalizes (handled
// in TrainingViewModel) and meals regenerate (NutritionTabView already observes).
//
// This is a thin editor over two settings — NOT a plan-editing surface. Future
// days regenerate from these inputs; today is re-resolved under the sacredness
// guard (planResolution); completed/in-progress sessions are never touched.
//

import SwiftData
import SwiftUI

struct ScheduleEditorView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @Query
    private var allSettings: [UserSettings]
    @Query
    private var allProfiles: [UserProfile]

    private var settings: UserSettings? { allSettings.first }
    private var profile: UserProfile? { allProfiles.first }

    /// Mon-first to match the ActiveDays bitmask (index 0 = Monday = 1<<0).
    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Set which days you play soccer and your training split. The week re-plans around it — completed sessions are never changed.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .listRowBackground(Color.clear)

                // Football / soccer days
                Section("Soccer / Football Days") {
                    HStack(spacing: TempoSpacing.xs) {
                        ForEach(Array(dayLabels.enumerated()), id: \.offset) { index, label in
                            let bit = 1 << index
                            let isOn = ((settings?.footballDaysRaw ?? 0) & bit) != 0
                            Button {
                                toggleFootballDay(bit: bit)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(label)
                                        .font(.tempoCaption1)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(isOn ? Color.tempoSignal : Color.tempoBgSecondary)
                                .foregroundStyle(isOn ? .white : Color.tempoTextSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm, style: .continuous))
                                .accessibilityLabel(dayNames[index])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, TempoSpacing.xxs)

                    let count = (settings?.footballDaysRaw ?? 0).nonzeroBitCount
                    Text("\(count) day\(count == 1 ? "" : "s") per week")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .listRowBackground(Color.tempoSurfaceCard)

                // Training split
                Section("Training Split") {
                    Picker(selection: Binding(
                        get: { settings?.trainingSplit ?? .pushPullLegs },
                        set: { setSplit($0) }
                    )) {
                        ForEach(TrainingSplit.allCases, id: \.self) { split in
                            Text(split.displayName).tag(split)
                        }
                    } label: {
                        Label("Split", systemImage: "dumbbell.fill")
                            .font(.tempoSubheadline)
                    }
                }
                .listRowBackground(Color.tempoSurfaceCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
    }

    // MARK: - Edits

    private func toggleFootballDay(bit: Int) {
        guard let s = settings else { return }
        s.footballDaysRaw ^= bit
        profile?.footballDaysRaw = s.footballDaysRaw // mirror for sync DTO parity
        HapticManager.selection()
        persistAndReplan()
    }

    private func setSplit(_ split: TrainingSplit) {
        guard let s = settings else { return }
        s.trainingSplit = split
        profile?.trainingSplitRaw = split.rawValue // mirror for sync DTO parity
        HapticManager.selection()
        persistAndReplan()
    }

    private func persistAndReplan() {
        try? modelContext.save()
        // Re-personalize: TrainingViewModel reloads the week + re-resolves today
        // under the sacredness guard; NutritionTabView regenerates meals. Posted
        // on every toggle; observers debounce.
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
    }
}
