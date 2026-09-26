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
    private var sent = false

    private let weekStart = WeeklyPlanService.weekStart()

    private static let quickPicks = [
        "Exam week — less time to cook",
        "Travelling part of the week",
        "Eating out more than usual",
        "Training harder this week",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    if sent {
                        sentState
                    } else {
                        form
                    }
                }
                .padding(TempoSpacing.screenEdge)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Next week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text("Anything different next week?")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(
                    "Week of \(weekStart.formatted(.dateTime.month(.wide).day())). Your usual routine is already in. 30 seconds — exams, travel, a dinner out, a new gym time."
                )
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            }
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                ForEach(Self.quickPicks, id: \.self) { pick in
                    Button {
                        said = said.isEmpty ? pick : "\(said). \(pick)"
                    } label: {
                        Label(pick, systemImage: "plus.circle")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            VoiceTextField(text: $said, placeholder: "Tap the mic and talk — or type.", minHeight: 120)
                .accessibilityIdentifier("weeklyCheckInSaid")
            if let errorMessage {
                Text(errorMessage)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoError)
            }
            Button {
                send()
            } label: {
                Group {
                    if isSending {
                        ProgressView()
                    } else {
                        Text(said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Same as usual — build it" : "Build my week")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)
            .disabled(isSending)
            .accessibilityIdentifier("weeklyCheckInBuild")
        }
    }

    private var sentState: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoSuccess)
            Text("On it.")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(
                "Your week is being built — every food checked, every day's macros solved. You'll get a notification when it's ready. You can close the app."
            )
            .font(.tempoBody)
            .foregroundStyle(Color.tempoTextSecondary)
        }
        .accessibilityIdentifier("weeklyCheckInSent")
    }

    private func send() {
        errorMessage = nil
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
            }
            isSending = false
        }
    }

    static func message(for error: Error) -> String {
        switch error as? APIError {
        case .subscriptionRequired?: "Weekly plans are a Pro feature."
        case .aiConsentRequired?: "Allow AI features in Settings to build plans."
        case .unauthorized?: "Sign in to build your week."
        case .networkError?,
             .timeout?,
             .connectionRefused?: "No connection. Try again when you're online."
        default: (error as? LocalizedError)?.errorDescription ?? "Couldn't start the plan. Try again."
        }
    }
}
