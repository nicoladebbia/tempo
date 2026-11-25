//
// GoalViews.swift
// Tempo
//
// How the goal shows up: a compact card on Today and a one-line chip other
// screens can drop in. Both draw a `GoalSnapshot`, so they always agree.
//

import SwiftData
import SwiftUI

// MARK: - GoalPace colour

extension GoalProgress.Pace {
    var tint: Color {
        switch self {
        case .ahead,
             .reached: TideTone.mint
        case .onTrack: TideTone.sky
        case .behind: TideTone.amber
        case .noReading: Tide.text2
        }
    }
}

// MARK: - GoalSnapshotLoader

/// Keeps a `GoalSnapshot` current for the view that owns it: on appear, when the
/// app comes to the front, and when a goal or a workout changes.
private struct GoalSnapshotLoader: ViewModifier {
    let kinds: Set<GoalKind>?
    @Binding var snapshot: GoalSnapshot?

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.scenePhase)
    private var scenePhase
    @Query
    private var settings: [UserSettings]

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase) {
                if scenePhase == .active {
                    reload()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoGoalChanged)) { _ in reload() }
            .onReceive(NotificationCenter.default.publisher(for: .tempoWorkoutChanged)) { _ in reload() }
    }

    private func reload() {
        let next = GoalReader.snapshot(
            kinds: kinds, unit: settings.first?.weightUnit ?? .kg, in: modelContext
        )
        if next != snapshot {
            snapshot = next
        }
    }
}

private extension View {
    func goalSnapshot(kinds: Set<GoalKind>?, into snapshot: Binding<GoalSnapshot?>) -> some View {
        modifier(GoalSnapshotLoader(kinds: kinds, snapshot: snapshot))
    }
}

// MARK: - GoalProgressChip

/// One line of goal progress for Train > Progress, Body progress and the Fuel
/// hero. Shows nothing when there is no goal of a kind it is asked for.
///
///     GoalProgressChip(kinds: [.liftE1RM])
struct GoalProgressChip: View {
    var kinds: Set<GoalKind>?
    var onOpen: (() -> Void)?

    @State
    private var snapshot: GoalSnapshot?

    var body: some View {
        // A concrete container hosts the loading modifiers, so they run even
        // while there is nothing to draw.
        VStack(spacing: 0) {
            if let snapshot {
                chip(snapshot)
            }
        }
        .goalSnapshot(kinds: kinds, into: $snapshot)
    }

    @ViewBuilder
    private func chip(_ snapshot: GoalSnapshot) -> some View {
        let content = HStack(spacing: Tide.s2) {
            Image(systemName: snapshot.kind.icon)
                .font(Tide.bodyStrong)
                .foregroundStyle(snapshot.progress.pace.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.headline)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(snapshot.paceLine) · \(snapshot.nowText) · \(snapshot.daysLeftText)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .tideTintedCard(snapshot.progress.pace.tint, padding: Tide.s3, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goal.chip")
        if let onOpen {
            Button(action: onOpen) { content }
                .buttonStyle(.plain)
        } else {
            // Nothing to open from here, so the chip explains the pace instead.
            content
                .explains(Explainer.goalPace(snapshot.progress.pace).showing(snapshot.paceLine))
                .accessibilityIdentifier("goal.chip")
        }
    }
}

extension Sequence<Goal> {
    /// True when one of these is an active goal of one of `kinds`. A screen with a
    /// spaced stack asks this first, so a chip that would draw nothing leaves no gap.
    func hasActive(of kinds: Set<GoalKind>) -> Bool {
        contains { $0.isActive && kinds.contains($0.kind) }
    }
}

// MARK: - TodayGoalCard

/// The goal on Today: the target, how far along, and whether the line is kept.
struct TodayGoalCard: View {
    var onOpen: () -> Void

    @State
    private var snapshot: GoalSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot {
                Button(action: onOpen) {
                    card(snapshot)
                }
                .buttonStyle(TodayPressStyle())
                .accessibilityIdentifier("today.goal")
            }
        }
        .goalSnapshot(kinds: nil, into: $snapshot)
    }

    private func card(_ snapshot: GoalSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Goal", trailing: snapshot.daysLeftText)
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(snapshot.headline)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tide.s2)
            }
            TideLevelBar(
                progress: snapshot.progress.fraction, color: snapshot.progress.pace.tint, height: Tide.bar
            )
            .accessibilityHidden(true)
            HStack(spacing: Tide.s2) {
                Text(snapshot.paceLine)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(snapshot.progress.pace.tint)
                Spacer(minLength: Tide.s2)
                Text(snapshot.nowText)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
        }
        .tideCard()
        .contentShape(.rect(cornerRadius: Tide.cardRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Goal. \(snapshot.headline). \(snapshot.paceLine). Now \(snapshot.nowText). \(snapshot.daysLeftText)."
        )
        .accessibilityHint("Opens the goal")
    }
}
