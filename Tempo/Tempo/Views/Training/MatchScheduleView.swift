//
// MatchScheduleView.swift
// Tempo
//
// Add + delete DATED matches (docs/INTELLIGENT_TRAINING_SYSTEM.md §9 D3,
// §14 mid-week-match trigger). Distinct from the recurring football-weekday
// chips in TrainingSettingsDetailView: that sets "I usually play Tue/Thu"; this logs
// "there's a game on Saturday the 14th vs Inter."
//
// On any change (add/delete) it posts `.tempoTrainingSettingsChanged` — the SAME
// notification the schedule editor uses — so the training week re-periodizes
// deterministically (T-0 match day + T-1 no-heavy-legs around the new fixture).
//
// COST NOTE (CLAUDE.md AI guardrail): re-periodization here is the DETERMINISTIC
// week planner only (free). It deliberately does NOT reset lastAIHydratedWeekKey,
// so editing matches never re-fires the Sonnet weekly-plan call — that stays on
// its once-per-ISO-week budget. The brain picks up the new daysUntilNextMatch on
// its next normal once-daily run; no extra paid call is triggered by a match edit.
//

import SwiftData
import SwiftUI

// MARK: - MatchScheduleView

struct MatchScheduleView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    /// Upcoming + recent matches, soonest first. Past matches age out of the
    /// readiness math but stay visible briefly so a mistaken delete is obvious.
    @Query(sort: \Match.kickoff, order: .forward)
    private var allMatches: [Match]

    @State
    private var showingAdd = false

    private var upcoming: [Match] {
        let cutoff = Calendar.current.startOfDay(for: Date())
        return allMatches.filter { $0.kickoff >= cutoff }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Log your fixtures. Tempo periodizes the surrounding days — no heavy legs the day before, and the daily coach knows a match is coming."
                    )
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                }
                .listRowBackground(Color.clear)

                if upcoming.isEmpty {
                    Section {
                        Text("No matches scheduled.")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text3)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, Tide.s3)
                    }
                    .listRowBackground(Tide.fill)
                } else {
                    Section("Upcoming") {
                        ForEach(upcoming) { match in
                            matchRow(match)
                        }
                        .onDelete(perform: deleteUpcoming)
                    }
                    .listRowBackground(Tide.fill)
                }
            }
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
            .navigationTitle("Matches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                MatchEntrySheet { kickoff, opponent, competitive in
                    addMatch(kickoff: kickoff, opponent: opponent, competitive: competitive)
                }
            }
        }
    }

    private func matchRow(_ match: Match) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            HStack {
                Text(match.opponent.map { "vs \($0)" } ?? "Match")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Spacer()
                if !match.isCompetitive {
                    Text("Friendly")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
            }
            Text(match.kickoff.formatted(date: .abbreviated, time: .shortened))
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
        }
        .padding(.vertical, Tide.hair)
    }

    // MARK: - Mutations (each re-periodizes the week deterministically)

    private func addMatch(kickoff: Date, opponent: String?, competitive: Bool) {
        let match = Match(kickoff: kickoff, opponent: opponent, isCompetitive: competitive)
        modelContext.insert(match)
        persistAndReplan()
    }

    private func deleteUpcoming(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(upcoming[index])
        }
        persistAndReplan()
    }

    private func persistAndReplan() {
        modelContext.saveOrAlert("match schedule")
        HapticManager.selection()
        // Deterministic re-periodization only (see COST NOTE in the file header):
        // re-shapes T-0/T-1 around the new fixture without a paid AI call.
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
    }
}

// MARK: - MatchEntrySheet

private struct MatchEntrySheet: View {
    @Environment(\.dismiss)
    private var dismiss

    let onSave: (_ kickoff: Date, _ opponent: String?, _ competitive: Bool) -> Void

    @State
    private var kickoff = MatchEntrySheet.defaultKickoff()
    @State
    private var opponent = ""
    @State
    private var competitive = true

    /// Tomorrow at 7PM — the common case (an evening fixture), still editable.
    private static func defaultKickoff() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    DatePicker(
                        "Kickoff",
                        selection: $kickoff,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                .listRowBackground(Tide.fill)

                Section("Opponent (optional)") {
                    TextField("e.g. Inter Miami", text: $opponent)
                        .textInputAutocapitalization(.words)
                }
                .listRowBackground(Tide.fill)

                Section {
                    Toggle("Competitive fixture", isOn: $competitive)
                } footer: {
                    Text("Competitive matches get the full taper — no heavy legs the day before. Turn off for a casual scrimmage.")
                        .font(Tide.caption)
                }
                .listRowBackground(Tide.fill)
            }
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
            .navigationTitle("Add Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Tide.text2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(kickoff, trimmed.isEmpty ? nil : trimmed, competitive)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
