//
//  ScheduleSettingsDetailView.swift
//  Tempo
//
//  Schedule: wake, bedtime and leisure on a 24-hour dial.
//

import SwiftData
import SwiftUI

// MARK: - ScheduleSettingsDetailView

struct ScheduleSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    @State
    private var wakeTime = Date()
    @State
    private var bedtime = Date()
    @State
    private var leisureTime = Date()
    /// The three times above start as placeholders until `loadSettings` runs.
    @State
    private var hasLoaded = false

    var body: some View {
        TideSettingsPage {
            // Sleep-window summary (computed from bedtime → wake). Hidden until the
            // saved times are in, and rebuilt then, so the ring never plays a
            // sweep from placeholder values.
            sleepWindowCard
                .id(hasLoaded)
                .opacity(hasLoaded ? 1 : 0)

            SettingsFormCard(
                title: "Daily rhythm",
                footnote: "Leisure is when your evening wind-down starts. Tempo uses these to time meals, study, and recovery prompts."
            ) {
                SettingsControlRow(label: "Wake Time", icon: "sunrise.fill") {
                    DatePicker("Wake Time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .onChange(of: wakeTime) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings?.wakeTimeMinutes = (comps.hour ?? 6) * 60 + (comps.minute ?? 0)
                    save()
                }

                SettingsRowDivider()

                SettingsControlRow(label: "Bedtime Target", icon: "moon.fill") {
                    DatePicker("Bedtime Target", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .onChange(of: bedtime) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings?.bedtimeTargetMinutes = (comps.hour ?? 22) * 60 + (comps.minute ?? 30)
                    save()
                }

                SettingsRowDivider()

                // Leisure is a TIME-OF-DAY (when wind-down starts), validated
                // 0..<1440 alongside wake/bedtime — not a duration.
                SettingsControlRow(label: "Leisure Time", icon: "hourglass") {
                    DatePicker("Leisure Time", selection: $leisureTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .onChange(of: leisureTime) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings?.leisureTimeMinutes = (comps.hour ?? 19) * 60 + (comps.minute ?? 30)
                    save()
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSettings() }
    }

    /// The whole day as one dial: the night, the wind-down before it and the
    /// day between. It moves as the three times below are changed.
    private var sleepWindowCard: some View {
        TideSettingsHero {
            TideLabel("Your day")
            SettingsRingHero {
                SettingsRing(arcs: dialArcs, markers: dialMarkers) {
                    VStack(spacing: Tide.hair) {
                        HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                            TideNumber("\(sleepWindow.hours)", unit: "h", size: Tide.numeralS, relativeTo: .title2)
                            if sleepWindow.minutes > 0 {
                                TideNumber("\(sleepWindow.minutes)", unit: "m", size: Tide.numeralS, relativeTo: .title2)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                        Text("Sleep").tideLabel(Tide.text3)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(sleepWindowText) planned sleep window")
                }
            } key: {
                SettingsLegendRow(color: mood.accent, title: "Wake", value: clock(wakeTime))
                SettingsLegendRow(color: Tide.streak, title: "Wind-down", value: clock(leisureTime))
                SettingsLegendRow(color: Tide.settingsNight, title: "Bedtime", value: clock(bedtime))
            }
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Minutes of night, bedtime to wake, wrapping past midnight. A bedtime
    /// equal to the wake time is a whole day, as it always was.
    private var nightMinutes: Int {
        let span = ((minutes(wakeTime) - minutes(bedtime)) % Self.day + Self.day) % Self.day
        return span == 0 ? Self.day : span
    }

    private var sleepWindow: (hours: Int, minutes: Int) {
        (nightMinutes / 60, nightMinutes % 60)
    }

    private var sleepWindowText: String {
        sleepWindow.minutes == 0 ? "\(sleepWindow.hours)h" : "\(sleepWindow.hours)h \(sleepWindow.minutes)m"
    }

    private static let day = 24 * 60

    /// Day, wind-down, night: in that order from the wake time round to the next one.
    private var dialArcs: [SettingsArc] {
        let day = Double(Self.day)
        let night = Double(nightMinutes)
        var windDown = Double(((minutes(bedtime) - minutes(leisureTime)) % Self.day + Self.day) % Self.day)
        if windDown > day - night {
            // Leisure sits inside the night: there is no wind-down stretch.
            windDown = 0
        }
        let awake = day - night - windDown
        let wake = Double(minutes(wakeTime)) / day
        return [
            SettingsArc(id: "day", start: wake, length: awake / day, color: Tide.settingsDay),
            SettingsArc(id: "wind", start: wake + awake / day, length: windDown / day, color: Tide.streak),
            SettingsArc(id: "night", start: wake + (awake + windDown) / day, length: night / day, color: Tide.settingsNight),
        ]
    }

    private var dialMarkers: [SettingsRingMarker] {
        let day = Double(Self.day)
        return [
            SettingsRingMarker(id: "wake", position: Double(minutes(wakeTime)) / day, color: mood.accent),
            SettingsRingMarker(id: "wind", position: Double(minutes(leisureTime)) / day, color: Tide.streak),
            SettingsRingMarker(id: "bed", position: Double(minutes(bedtime)) / day, color: Tide.settingsNight),
        ]
    }

    private func loadSettings() {
        defer { hasLoaded = true }
        guard let s = settings else {
            return
        }
        wakeTime = dateFromMinutes(s.wakeTimeMinutes)
        bedtime = dateFromMinutes(s.bedtimeTargetMinutes)
        leisureTime = dateFromMinutes(s.leisureTimeMinutes)
    }

    private func save() {
        try? modelContext.save()
    }

    private func dateFromMinutes(_ totalMinutes: Int) -> Date {
        var comps = DateComponents()
        comps.hour = totalMinutes / 60
        comps.minute = totalMinutes % 60
        return Calendar.current.date(from: comps) ?? Date()
    }
}
