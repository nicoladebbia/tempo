//
// SetupChecklistViews.swift
// Tempo
//
// "Get set up": the card on Today (what is still open, with "Later") and the
// page in Settings (every line, always reachable). Both draw a
// `SetupChecklist` built from the app's real state.
//

import SwiftData
import SwiftUI

// MARK: - SetupChecklistCard

/// The Today card: the lines still open, at most three, and "Later".
struct SetupChecklistCard: View {
    let checklist: SetupChecklist
    /// Runs the line's action (opens the screen that finishes it).
    let onStep: (SetupStep) -> Void
    let onLater: () -> Void

    /// Open lines shown on Today. The rest are in Settings.
    static let visibleLines = 3

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        let open = checklist.remaining
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Get set up", trailing: "\(checklist.doneCount) of \(checklist.total) done")
            VStack(spacing: 0) {
                ForEach(open.prefix(Self.visibleLines)) { line in
                    Button { onStep(line.step) } label: {
                        row(line.step)
                    }
                    .buttonStyle(TodayPressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.setup.\(line.step.id)")
                }
            }
            if open.count > Self.visibleLines {
                Text("+ \(open.count - Self.visibleLines) more in Settings")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            Button("Later", action: onLater)
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("today.setup.later")
        }
        .tideCard()
        .accessibilityIdentifier("today.setup")
    }

    private func row(_ step: SetupStep) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: step.icon)
                .font(Tide.headline)
                .foregroundStyle(mood.accent)
                .frame(minWidth: Tide.icon, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Text(step.detail)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Tide.s2)
            Image(systemName: "chevron.right")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Tide.hit + Tide.s2)
        .contentShape(.rect)
    }
}

// MARK: - SetupChecklistPage

/// Settings > Get set up. Every line, done or not, each opening the screen that finishes it.
struct SetupChecklistPage: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    @AppStorage("healthKitAuthorized")
    private var healthKitAuthorized = false
    @AppStorage("hasCompletedSetup")
    private var dismissedOnToday = false

    @State
    private var checklist = SetupChecklist(.init())

    var body: some View {
        TideSettingsPage {
            SettingsFormCard(
                title: "\(checklist.doneCount) of \(checklist.total) done",
                footnote: footnote
            ) {
                ForEach(Array(checklist.lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 {
                        SettingsRowDivider()
                    }
                    row(line)
                }
            }

            if dismissedOnToday, !checklist.isConfigured {
                Button("Show this on Today again") {
                    dismissedOnToday = false
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("setup.showOnToday")
            }
        }
        .navigationTitle("Get set up")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .task(id: healthKitAuthorized) { reload() }
    }

    private var footnote: String {
        checklist.isConfigured
            ? "You are set up. Health and Whoop make Tempo sharper but are optional."
            : "Each line opens the screen that finishes it."
    }

    @ViewBuilder
    private func row(_ line: SetupChecklist.Line) -> some View {
        let step = line.step
        if line.done {
            SettingsStatusRow(
                icon: step.icon, title: step.title, status: "Done", statusColor: TideTone.mint, showsChevron: false
            )
            .accessibilityIdentifier("setup.\(step.id)")
        } else {
            switch step {
            case .health:
                Button {
                    Task {
                        try? await services.healthKit.requestAuthorization()
                        reload()
                    }
                } label: {
                    SettingsNavRow(icon: step.icon, title: step.title, subtitle: step.detail)
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityIdentifier("setup.\(step.id)")
            case .whoop:
                link(step) { WhoopConnectionView() }
            case .food:
                link(step) { FuelSetupView(embedded: true) }
            case .training:
                link(step) { TrainingSettingsDetailView() }
            case .tasks:
                link(step) { NonNegotiableSetupView() }
            }
        }
    }

    private func link(_ step: SetupStep, @ViewBuilder destination: () -> some View) -> some View {
        NavigationLink {
            destination()
        } label: {
            SettingsNavRow(icon: step.icon, title: step.title, subtitle: step.detail)
        }
        .buttonStyle(.tideSettingsRow)
        .accessibilityIdentifier("setup.\(step.id)")
    }

    private func reload() {
        checklist = SetupChecklist(SetupChecklistLoader.signals(
            healthAllowed: healthKitAuthorized,
            whoopConnected: services.whoop.providesRealData,
            resolved: true,
            in: modelContext
        ))
    }
}
