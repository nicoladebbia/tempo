//
//  ModesSettingsDetailView.swift
//  Tempo
//
//  Modes: Weekend and Exam.
//

import SwiftData
import SwiftUI

// MARK: - ModesSettingsDetailView

struct ModesSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    @State
    private var weekendMode = false
    @State
    private var examMode = false
    @State
    private var examEndDate = Date()

    /// Which modes are bending the plan right now, as the switches below show
    /// them: the answer in words, and one tile per mode that lights up.
    private var modesHero: some View {
        let active = [weekendMode ? "Weekend" : nil, examMode ? "Exam" : nil].compactMap(\.self)
        return TideSettingsHero {
            TideLabel("Active now")
            HStack(alignment: .center, spacing: Tide.s3) {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(active.isEmpty ? "Standard day" : active.joined(separator: " \u{00B7} "))
                        .font(Tide.title)
                        .foregroundStyle(active.isEmpty ? Tide.text : mood.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(active.isEmpty ? "No mode is changing your plan." : "Your plan is adjusted while this is on.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Tide.s2)
                if !typeSize.isAccessibilitySize {
                    HStack(spacing: Tide.s2) {
                        TideIconTile(
                            systemName: "party.popper.fill", tint: weekendMode ? mood.accent : Tide.text3,
                            size: Tide.settingsBigTile
                        )
                        TideIconTile(
                            systemName: "pencil.and.list.clipboard", tint: examMode ? mood.accent : Tide.text3,
                            size: Tide.settingsBigTile
                        )
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : Tide.snap, value: active)
        .accessibilityElement(children: .combine)
    }

    /// Whole days from today to the exam end date, never below zero.
    private var examDaysLeft: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.startOfDay(for: examEndDate)
        return max(0, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    var body: some View {
        TideSettingsPage {
            modesHero

            SettingsModeCard(
                icon: "party.popper.fill",
                title: "Weekend Mode",
                detail: "Relaxes your schedule and eases accountability on Saturdays and Sundays.",
                isOn: $weekendMode
            )
            .onChange(of: weekendMode) { _, newValue in
                settings?.weekendMode = newValue
                save()
            }

            SettingsModeCard(
                icon: "pencil.and.list.clipboard",
                title: "Exam Mode",
                detail: examMode
                    ? "Study is prioritised and training load reduced until your exam end date."
                    : "Prioritise study and reduce training load during exam periods.",
                isOn: $examMode
            ) {
                if examMode {
                    TideSettingsHairline(inset: 0)
                    SettingsControlRow(label: "Ends", icon: "calendar.badge.clock") {
                        DatePicker("Ends", selection: $examEndDate, in: Date()..., displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(.horizontal, -Tide.s4)
                    .onChange(of: examEndDate) { _, newValue in
                        settings?.examModeEndDate = newValue
                        save()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                        TideNumber("\(examDaysLeft)", unit: examDaysLeft == 1 ? "day left" : "days left", size: Tide.numeralS, relativeTo: .title2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .onChange(of: examMode) { _, newValue in
                settings?.examMode = newValue
                if newValue, settings?.examModeEndDate == nil {
                    settings?.examModeEndDate = examEndDate
                }
                save()
            }
        }
        .animation(reduceMotion ? nil : Tide.snap, value: examMode)
        .sensoryFeedback(.selection, trigger: weekendMode)
        .sensoryFeedback(.selection, trigger: examMode)
        .navigationTitle("Modes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            weekendMode = settings?.weekendMode ?? false
            examMode = settings?.examMode ?? false
            examEndDate = settings?.examModeEndDate ?? Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date()
        }
    }

    private func save() {
        try? modelContext.save()
    }
}
