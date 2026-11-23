//
// VenueProposalCard.swift
// Tempo
//
// The §16.2 propose-then-confirm flow: "Gym day — your usual 4:00 PM? [Yes]
// [Change]". NOT a blank daily form (Decision #6) and NOT a gate (§15.4) —
// the coach runs with or without an answer; a confirmation upgrades today's
// prompt context (when it lands before the once-daily run) and is always the
// highest-quality learning sample for the pattern.
//
// Visibility honesty (§16.3): the card only renders when a learned pattern
// exists for today's weekday (≥3 completed samples — rows below the gate are
// never persisted). Under 5 samples it phrases soft ("Gym today?"); at ≥5 it
// asserts the usual time. Already answered or dismissed → renders nothing.
//
// The body roots in an always-present VStack hosting `.task` — never a Group
// whose first child is EmptyView (the D1 MorningCheckInCard lesson, CLAUDE.md).
//

import SwiftData
import SwiftUI

struct VenueProposalCard: View {
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var pattern: VenuePattern?
    @State
    private var answeredToday = false
    @State
    private var dismissed = false
    @State
    private var changing = false
    @State
    private var pickedVenue: TrainingVenue = .gym
    @State
    private var pickedTime = Date()

    var body: some View {
        VStack(spacing: 0) {
            if !dismissed, !answeredToday, let pattern, let venue = pattern.venue {
                card(pattern: pattern, venue: venue)
            }
        }
        .task { load() }
    }

    // MARK: - Card

    private func card(pattern: VenuePattern, venue: TrainingVenue) -> some View {
        TrainBanner(
            systemImage: "mappin.and.ellipse",
            label: "Venue check",
            title: proposalText(pattern: pattern, venue: venue)
        ) {
            if changing {
                changePickers
            } else {
                HStack(spacing: Tide.s2) {
                    Button {
                        confirm(venue: venue, startMin: pattern.medianStartMin)
                    } label: {
                        Text("Yes")
                    }
                    .buttonStyle(.trainBanner())

                    Button {
                        pickedVenue = venue
                        pickedTime = timeFromMinutes(pattern.medianStartMin)
                        withAnimation(Tide.snap) { changing = true }
                    } label: {
                        Text("Change")
                    }
                    .buttonStyle(.trainBanner(filled: false))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss venue check")
        }
    }

    private var changePickers: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack {
                Text("Venue")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                Spacer()
                Picker("Venue", selection: $pickedVenue) {
                    ForEach(TrainingVenue.allCases, id: \.self) { venue in
                        Text(venue.displayName).tag(venue)
                    }
                }
                .tint(Tide.text)
            }
            HStack {
                Text("Time")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                Spacer()
                DatePicker("", selection: $pickedTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            Button {
                confirm(
                    venue: pickedVenue,
                    startMin: VenuePatternLearner.minutesAfterMidnight(pickedTime)
                )
            } label: {
                Text("Confirm")
            }
            .buttonStyle(.trainBanner())
        }
    }

    // MARK: - Copy

    private func proposalText(pattern: VenuePattern, venue: TrainingVenue) -> String {
        if pattern.sampleCount >= VenuePatternMath.minSamplesToAssertTime,
           let start = pattern.medianStartMin
        {
            return "\(venue.displayName) day — your usual \(VenuePatternMath.clockLabel(start))?"
        }
        return "\(venue.displayName) today?"
    }

    // MARK: - Data

    private func load() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)

        answeredToday = !(((try? modelContext.fetch(FetchDescriptor<VenueConfirmation>(
            predicate: #Predicate { $0.dayKey == today }
        ))) ?? []).isEmpty)

        pattern = ((try? modelContext.fetch(FetchDescriptor<VenuePattern>(
            predicate: #Predicate { $0.weekday == weekday }
        ))) ?? []).first
    }

    private func confirm(venue: TrainingVenue, startMin: Int?) {
        let today = Calendar.current.startOfDay(for: Date())
        modelContext.insert(VenueConfirmation(dayKey: today, venue: venue, startMin: startMin))
        modelContext.saveOrAlert("venue answer")
        // The answer is the highest-quality sample — fold it in immediately.
        VenuePatternLearner.recompute(modelContext: modelContext)
        answeredToday = true
        HapticManager.selection()
    }

    private func timeFromMinutes(_ minutes: Int?) -> Date {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        return cal.date(byAdding: .minute, value: minutes ?? 16 * 60, to: base) ?? base
    }
}
