//
// SupplementTimingSection.swift
// Tempo
//
// The user's override of WHEN a supplement is taken — Auto (the app decides:
// pin/override/plan-timing/kind-default, see `SupplementScheduleEngine`), a
// picked anchor (breakfast, bedtime, ...), or a fixed clock time — plus a
// per-supplement reminders switch. Meant to be embedded in the shelf's edit
// sheet (`SupplementsView.SupplementEditSheet`, owned by another lane); this
// file only defines the section, it does not touch that sheet.
//
// Writes straight to the `Supplement` it's given and saves immediately
// (rather than waiting for the host sheet's own Save button) so the timing
// engine and reminder scheduler see the change the moment it's made, even if
// the host sheet is dismissed by swipe. Posts `.tempoSupplementsChanged` on
// every edit so `SupplementReminderScheduler` rebuilds.
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI

// MARK: - SupplementTimingMode

private enum SupplementTimingMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case anchor = "Anchor"
    case fixed = "Fixed time"

    var id: String {
        rawValue
    }
}

// MARK: - SupplementTimingSection

struct SupplementTimingSection: View {
    @Bindable var supplement: Supplement

    @Environment(\.modelContext)
    private var modelContext

    @State
    private var mode: SupplementTimingMode
    @State
    private var selectedAnchor: SupplementTimingAnchor
    @State
    private var fixedTime: Date

    init(supplement: Supplement) {
        self.supplement = supplement
        let anchor = supplement.timingAnchorOverride
        if supplement.pinnedMinutes != nil {
            _mode = State(initialValue: .fixed)
        } else if anchor != nil {
            _mode = State(initialValue: .anchor)
        } else {
            _mode = State(initialValue: .auto)
        }
        _selectedAnchor = State(initialValue: anchor ?? SupplementTimingAnchor.defaultAnchor(for: supplement.kind))
        let minutes = supplement.pinnedMinutes ?? 480
        _fixedTime = State(initialValue: Calendar.current
            .date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date())
    }

    private var remindersEnabled: Binding<Bool> {
        Binding(
            get: { supplement.remindersEnabled ?? true },
            set: {
                supplement.remindersEnabled = $0
                persist()
            }
        )
    }

    var body: some View {
        Section {
            Picker("When", selection: $mode) {
                ForEach(SupplementTimingMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in
                applyMode()
            }

            switch mode {
            case .auto:
                EmptyView()
            case .anchor:
                Picker("Anchor", selection: $selectedAnchor) {
                    ForEach(SupplementTimingAnchor.allCases, id: \.rawValue) { anchor in
                        Text(anchor.displayName).tag(anchor)
                    }
                }
                .onChange(of: selectedAnchor) { _, newValue in
                    supplement.timingAnchorOverride = newValue
                    supplement.pinnedMinutes = nil
                    persist()
                }
            case .fixed:
                DatePicker("Time", selection: $fixedTime, displayedComponents: .hourAndMinute)
                    .onChange(of: fixedTime) { _, newValue in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        supplement.pinnedMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
                        supplement.timingAnchorOverride = nil
                        persist()
                    }
            }

            Toggle("Remind me", isOn: remindersEnabled)
        } header: {
            Text("Timing")
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        switch mode {
        case .auto:
            "The app decides — from your plan's timing, or a sensible default for this kind of supplement."
        case .anchor:
            "Anchored to your real day — the app resolves it to a clock time from your meals, training, and sleep."
        case .fixed:
            "Always at this exact time, every day."
        }
    }

    private func applyMode() {
        switch mode {
        case .auto:
            supplement.timingAnchorOverride = nil
            supplement.pinnedMinutes = nil
        case .anchor:
            supplement.timingAnchorOverride = selectedAnchor
            supplement.pinnedMinutes = nil
        case .fixed:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: fixedTime)
            supplement.pinnedMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
            supplement.timingAnchorOverride = nil
        }
        persist()
    }

    /// Saves immediately when the supplement is already in the context (an
    /// existing shelf item). A brand-new, not-yet-inserted supplement (the
    /// "Add" flow) just keeps the in-memory change — the host sheet's own
    /// insert + save picks it up.
    private func persist() {
        supplement.updatedAt = Date()
        try? modelContext.save()
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }
}
