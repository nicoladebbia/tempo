//
// MatchProposalCard.swift
// Tempo
//
// §18.4 — calendar-detected football, confirm-gated. The calendar keyword
// detector is deliberately loose ("game", "practice", "partita"…), so detected
// events are PROPOSED here instead of silently repainting the training week:
// confirming inserts a real `Match` (the same dated-fixture machinery
// MatchScheduleView feeds), and the settings-changed fan-out replans T-1/T-0
// around it. Dismissing remembers the event so it never re-proposes. A false
// positive therefore costs one tap, never a lost gym day.
//
// Lifecycle rule (D1 lesson): the `.task` lives on an always-present VStack —
// never on a conditional whose first branch is EmptyView.
//

import SwiftData
import SwiftUI

struct MatchProposalCard: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Query
    private var allSettings: [UserSettings]
    @Query
    private var matches: [Match]

    /// Dismissed proposals as "title|yyyy-MM-dd" keys, comma-joined.
    /// CalendarEvent has no stable id, so title+day is the identity — a
    /// renamed event legitimately re-proposes.
    @AppStorage("tempo.matchProposal.dismissedKeys")
    private var dismissedKeysRaw = ""

    @State
    private var proposals: [CalendarEvent] = []

    private var cal: Calendar {
        Calendar.current
    }

    var body: some View {
        VStack(spacing: Tide.s2) {
            ForEach(proposals.prefix(2), id: \.startDate) { event in
                proposalRow(event)
            }
        }
        .task {
            await loadProposals()
        }
    }

    // MARK: - Row

    private func proposalRow(_ event: CalendarEvent) -> some View {
        // The ask is about one day, so the card opens on that day: its weekday
        // over its date, in the caution tint a match always carries.
        TrainAskCard(
            label: "Found on your calendar",
            tint: TideTrain.caution,
            title: "\u{201C}\(event.title)\u{201D} — \(dayLabel(event.startDate)). Match day?",
            message: "Confirming locks it into the match schedule and re-plans the days around it."
        ) {
            TrainFigureTile(date: event.startDate, tint: TideTrain.caution)
        } actions: {
            Button {
                confirm(event)
            } label: {
                Label("Add match", systemImage: "sportscourt")
            }
            .buttonStyle(.trainBanner(tint: TideTrain.caution))

            Button {
                dismissProposal(event)
            } label: {
                Text("Not a match")
            }
            .buttonStyle(.trainQuiet)
        }
    }

    // MARK: - Data

    private func loadProposals() async {
        let today = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 7, to: today) else {
            return
        }
        let range = DateInterval(start: today, end: end)

        // Warm the calendar cache (detect* reads the sync cache).
        _ = try? await services.calendar.fetchEvents(for: range)

        let footballDays = ActiveDays(rawValue: allSettings.first?.footballDaysRaw ?? 0)
        let knownMatchDays = Set(matches.map { cal.startOfDay(for: $0.kickoff) })
        let dismissed = Set(dismissedKeysRaw.split(separator: ",").map(String.init))

        proposals = services.calendar.detectFootballEvents(in: range).filter { event in
            let day = cal.startOfDay(for: event.startDate)
            // Already covered by the recurring weekday cadence → nothing to add.
            if footballDays.isActive(on: cal.component(.weekday, from: day)) {
                return false
            }
            // Already an explicit dated Match → nothing to add.
            if knownMatchDays.contains(day) {
                return false
            }
            if dismissed.contains(proposalKey(event)) {
                return false
            }
            return day >= today
        }
    }

    // MARK: - Actions

    private func confirm(_ event: CalendarEvent) {
        let match = Match(
            kickoff: event.startDate,
            // The raw title is the best label we have ("Partita vs Inter").
            opponent: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
            isCompetitive: true // protect by default — same as the model's default
        )
        modelContext.insert(match)
        modelContext.saveOrAlert("match")
        // Same fan-out MatchScheduleView posts on add — replans the week.
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
        HapticManager.notification(.success)
        proposals.removeAll { proposalKey($0) == proposalKey(event) }
    }

    private func dismissProposal(_ event: CalendarEvent) {
        var keys = dismissedKeysRaw.split(separator: ",").map(String.init)
        keys.append(proposalKey(event))
        // Cap the remembered set — old keys are dead weight once the event is past.
        dismissedKeysRaw = keys.suffix(40).joined(separator: ",")
        HapticManager.selection()
        proposals.removeAll { proposalKey($0) == proposalKey(event) }
    }

    // MARK: - Helpers

    private func proposalKey(_ event: CalendarEvent) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        // Commas would corrupt the comma-joined store.
        let safeTitle = event.title.replacingOccurrences(of: ",", with: " ")
        return "\(safeTitle)|\(f.string(from: event.startDate))"
    }

    private func dayLabel(_ date: Date) -> String {
        if cal.isDateInToday(date) {
            return "today"
        }
        if cal.isDateInTomorrow(date) {
            return "tomorrow"
        }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
