//
// WeeklyCheckInView.swift
// Tempo
//
// The 30-second Sunday check-in: anything different about next week (exam,
// trip, a dinner out)? Say it or type it — or skip — and the server builds
// the week around the routine from Fuel setup plus this.
//

import SwiftData
import SwiftUI

struct WeeklyCheckInView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var said = ""
    @State
    private var isSending = false
    @State
    private var errorMessage: String?
    @State
    private var blocker: AIBlocker?
    @State
    private var sent = false
    @Environment(\.tideMood)
    private var mood

    private let weekStart = WeeklyPlanService.weekStart()

    private static let quickPicks = [
        "Exam week — less time to cook",
        "Travelling part of the week",
        "Eating out more than usual",
        "Training harder this week",
    ]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    if sent {
                        sentState
                    } else {
                        form
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s3)
                .padding(.bottom, Tide.s8)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .tidePage()
            .navigationTitle("Next week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Tide.s5) {
            VStack(alignment: .leading, spacing: Tide.s2) {
                Text("Anything different next week?")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Week of \(weekStart.formatted(.dateTime.month(.wide).day())). Your usual routine is already in. 30 seconds — exams, travel, a dinner out, a new gym time."
                )
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
            quickPickList
            VoiceTextField(text: $said, placeholder: "Tap the mic and talk — or type.", minHeight: 120)
                .accessibilityIdentifier("weeklyCheckInSaid")
            if let blocker {
                AIBlockerCard(blocker: blocker, message: PlanGenerationBlocker(from: blocker).message) {
                    self.blocker = nil
                    send()
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                send()
            } label: {
                Group {
                    if isSending {
                        ProgressView()
                            .tint(Tide.ink)
                    } else {
                        Text(said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Same as usual — build it" : "Build my week")
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .buttonStyle(.tidePrimary)
            .disabled(isSending)
            .accessibilityIdentifier("weeklyCheckInBuild")
        }
    }

    /// Tap a line to add it to what you say. The lines are long, so each one
    /// is a full-width row that wraps instead of a chip that cuts.
    private var quickPickList: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.quickPicks.enumerated()), id: \.element) { index, pick in
                Button {
                    HapticManager.lightImpact()
                    said = said.isEmpty ? pick : "\(said). \(pick)"
                } label: {
                    HStack(spacing: Tide.s3) {
                        Image(systemName: "plus.circle")
                            .font(Tide.headline)
                            .foregroundStyle(mood.accent)
                            .frame(width: Tide.icon, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(pick)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Tide.hit + Tide.s3)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if index < Self.quickPicks.count - 1 {
                    Divider()
                        .overlay(Tide.hairline)
                }
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private var sentState: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Image(systemName: "checkmark.circle.fill")
                .font(Tide.title)
                .foregroundStyle(Tide.good)
                .accessibilityHidden(true)
            Text("On it.")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            Text(
                "Your week is being built — every food checked, every day's macros solved. You'll get a notification when it's ready. You can close the app."
            )
            .font(Tide.body)
            .foregroundStyle(Tide.text2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("weeklyCheckInSent")
        .tideCard()
    }

    private func send() {
        errorMessage = nil
        blocker = nil
        isSending = true
        Task {
            // So the "ready" push can reach this phone.
            _ = try? await services.pushRegistration.requestAuthorizationAndRegister()
            do {
                let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
                try await WeeklyPlanService.shared.requestWeek(
                    checkIn: text.isEmpty ? nil : text,
                    weekStart: weekStart,
                    modelContext: modelContext,
                    deps: PlanDeps(services)
                )
                HapticManager.success()
                sent = true
            } catch {
                errorMessage = Self.message(for: error)
                blocker = AIBlocker(error)
            }
            isSending = false
        }
    }

    static func message(for error: Error) -> String {
        switch error as? APIError {
        case .subscriptionRequired?: PlanGenerationBlocker.proRequired.message
        case .aiConsentRequired?: PlanGenerationBlocker.aiConsentRequired.message
        case .unauthorized?: "Sign in to build your week."
        case .networkError?,
             .timeout?,
             .connectionRefused?: "No connection. Try again when you're online."
        default: (error as? LocalizedError)?.errorDescription ?? "Couldn't start the plan. Try again."
        }
    }
}
