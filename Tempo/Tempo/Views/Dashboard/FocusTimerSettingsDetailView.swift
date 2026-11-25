//
//  FocusTimerSettingsDetailView.swift
//  Tempo
//
//  Focus Timer: the three durations and the cycle they make.
//

import SwiftData
import SwiftUI

// MARK: - FocusTimerSettingsDetailView

struct FocusTimerSettingsDetailView: View {
    @Environment(\.tideMood)
    private var mood

    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    @State
    private var pomodoroDuration = 25
    @State
    private var breakDuration = 5
    @State
    private var longBreakDuration = 15

    var body: some View {
        TideSettingsPage {
            cyclePreviewCard

            SettingsFormCard(
                title: String(localized: "Durations"),
                footnote: String(localized: "A focus block runs, then a short break; after a few blocks you earn a long break.")
            ) {
                SettingsControlRow(label: String(localized: "Focus block"), icon: "timer") {
                    Stepper("\(pomodoroDuration) min", value: $pomodoroDuration, in: 10 ... 60, step: 5)
                        .font(Tide.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Tide.text2)
                        .fixedSize()
                }
                .onChange(of: pomodoroDuration) { _, newValue in
                    settings?.pomodoroDuration = newValue
                    save()
                }

                SettingsRowDivider()

                SettingsControlRow(label: String(localized: "Short break"), icon: "cup.and.saucer.fill") {
                    Stepper("\(breakDuration) min", value: $breakDuration, in: 3 ... 15)
                        .font(Tide.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Tide.text2)
                        .fixedSize()
                }
                .onChange(of: breakDuration) { _, newValue in
                    settings?.breakDuration = newValue
                    save()
                }

                SettingsRowDivider()

                SettingsControlRow(label: String(localized: "Long break"), icon: "cup.and.saucer") {
                    Stepper("\(longBreakDuration) min", value: $longBreakDuration, in: 10 ... 30, step: 5)
                        .font(Tide.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Tide.text2)
                        .fixedSize()
                }
                .onChange(of: longBreakDuration) { _, newValue in
                    settings?.longBreakDuration = newValue
                    save()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: pomodoroDuration)
        .sensoryFeedback(.selection, trigger: breakDuration)
        .sensoryFeedback(.selection, trigger: longBreakDuration)
        .navigationTitle("Focus Timer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pomodoroDuration = settings?.pomodoroDuration ?? 25
            breakDuration = settings?.breakDuration ?? 5
            longBreakDuration = settings?.longBreakDuration ?? 15
        }
    }

    /// One full round as a ring: four focus blocks with a short break after
    /// each of the first three, then the long break. It grows and shrinks
    /// with the steppers below.
    private var cyclePreviewCard: some View {
        TideSettingsHero {
            TideLabel(String(localized: "One round"))
            SettingsRingHero {
                SettingsRing(arcs: cycleArcs) {
                    VStack(spacing: Tide.hair) {
                        HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                            if cycleMinutes >= 60 {
                                TideNumber("\(cycleMinutes / 60)", unit: String(localized: "h", comment: "Hours unit, one letter"), size: Tide.numeralS, relativeTo: .title2)
                            }
                            TideNumber("\(cycleMinutes % 60)", unit: String(localized: "m", comment: "Minutes unit, one letter"), size: Tide.numeralS, relativeTo: .title2)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                        Text("4 blocks").tideLabel(Tide.text3)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("A round of four focus blocks takes \(cycleMinutes) minutes")
                }
            } key: {
                SettingsLegendRow(color: mood.accent, title: String(localized: "Focus block"), value: String(localized: "\(pomodoroDuration) min"))
                SettingsLegendRow(color: Tide.water, title: String(localized: "Short break"), value: String(localized: "\(breakDuration) min"))
                SettingsLegendRow(color: Tide.streak, title: String(localized: "Long break"), value: String(localized: "\(longBreakDuration) min"))
            }
        }
    }

    /// Focus, break, focus, break, focus, break, focus, long break.
    private var cycleMinutes: Int {
        Self.blocks * pomodoroDuration + (Self.blocks - 1) * breakDuration + longBreakDuration
    }

    private static let blocks = 4

    private var cycleArcs: [SettingsArc] {
        let total = Double(cycleMinutes)
        var parts: [(String, Int, Color)] = []
        for block in 0 ..< Self.blocks {
            parts.append(("focus\(block)", pomodoroDuration, mood.accent))
            parts.append(block < Self.blocks - 1 ? ("break\(block)", breakDuration, Tide.water) : ("long", longBreakDuration, Tide.streak))
        }
        var start = 0.0
        return parts.map { id, minutes, color in
            let length = Double(minutes) / total
            defer { start += length }
            return SettingsArc(id: id, start: start, length: length, color: color)
        }
    }

    private func save() {
        try? modelContext.save()
    }
}
