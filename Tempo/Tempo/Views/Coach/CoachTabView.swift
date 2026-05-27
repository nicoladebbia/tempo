//
// CoachTabView.swift
// Tempo
//
// Coach v2.1 Phase 8a — top-level host that owns the CoachViewModel,
// gates on the interview, and builds the system prompt on every send via
// CoachContextAssembler.
//
// This is the entry the main TabView routes to. It assembles all the
// adapters from Phase 7a (chat / summarizer / dispatcher) + the new
// Phase 8a extractor + evidence provider, and presents either the
// CoachInterviewView sheet or the live CoachChatView.
//
// Per .plans/coach-v2.1/05-ui-surfaces.md "Coach tab".
//

import SwiftData
import SwiftUI

// MARK: - CoachTabView

struct CoachTabView: View {
    /// Caller (the app's tab router) provides the APIClient so all the
    /// adapters share the same auth + retry infrastructure as the rest
    /// of the app.
    let apiClient: APIClient
    /// Optional sleep reader for the OutcomeEvidenceProvider. nil →
    /// uses NoopHKSleepReader (bedtime grading falls back to .unclear).
    var sleepReader: HKSleepReader = NoopHKSleepReader()
    /// Override for tests / previews. nil → real VoiceTranscriber.
    var voiceOverride: (any CoachVoiceControlling)?

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CoachViewModel?
    @State private var presentingInterview: Bool = false

    var body: some View {
        Group {
            if let viewModel {
                CoachChatView(
                    viewModel: viewModel,
                    systemPromptBuilder: { buildSystemPrompt() },
                    voice: voiceOverride ?? CoachVoiceController(),
                    voiceMode: currentVoiceMode()
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.tempoSignal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.tempoBgPrimary)
            }
        }
        .task {
            await bootstrapViewModelIfNeeded()
        }
        .sheet(isPresented: $presentingInterview) {
            CoachInterviewView { _ in
                presentingInterview = false
                // After interview saves, refresh the VM gate snapshot
                // so re-presentation doesn't fire.
                Task { await bootstrapViewModelIfNeeded(force: true) }
            }
        }
    }

    // MARK: - Bootstrap

    private func bootstrapViewModelIfNeeded(force: Bool = false) async {
        if viewModel != nil, !force { return }

        // Build the agent loop's adapters from APIClient.
        let chatClient = CoachChatAIClientAdapter(requester: apiClient)
        let summarizer = ConversationSummarizerAIClientAdapter(requester: apiClient)
        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(), // overridden per-conversation by Phase 6b
            turnIndex: 0
        )
        let service = CoachService(
            aiClient: chatClient,
            summarizerClient: summarizer,
            toolDispatcher: dispatcher
        )
        let extractor = PreferenceExtractorAdapter(requester: apiClient)
        let gate = interviewGate(from: modelContext)

        let vm = CoachViewModel(
            service: service,
            interviewGateProvider: { gate },
            extractorClient: extractor
        )
        viewModel = vm
        if vm.shouldPresentInterview() {
            presentingInterview = true
        } else {
            vm.loadOrStartConversation(context: modelContext)
        }

        // Register the evidence provider for the daily reset grader (idempotent).
        if DailyResetCoordinator.coachEvidenceProvider == nil {
            DailyResetCoordinator.coachEvidenceProvider = OutcomeEvidenceProviderImpl(
                modelContainer: modelContext.container,
                sleepReader: sleepReader
            )
        }
    }

    // MARK: - System prompt assembly

    /// Built fresh on every send so today-live + preferences reflect the
    /// latest SwiftData snapshot.
    private func buildSystemPrompt() -> String {
        let snapshot = CoachContextAssembler.assemble(
            modelContext: modelContext,
            todayLive: liveSnapshot(),
            calendarEvents: [], // calendar wire-up landed in Phase 5; the caller
                                // can extend this when a CalendarService is
                                // present in the environment.
            recentConversationSummaries: []
        )
        return snapshot.render()
    }

    /// Live-state snapshot for today. Minimal — the full HK/Whoop wiring
    /// lives in the existing nutrition/recovery view models; pulling
    /// it into this host belongs in a follow-up commit (Phase 8b sticks
    /// to memory UI).
    private func liveSnapshot() -> TodayLiveSnapshot {
        let plannedMealCount = (
            try? modelContext.fetch(FetchDescriptor<PlannedMeal>())
        )?.filter { Calendar.current.isDateInToday($0.dayDate) }.count ?? 0
        return TodayLiveSnapshot(
            date: Date(),
            dayType: nil,
            recoveryScore: nil,
            recoveryZone: nil,
            hrvMs: nil,
            restingHR: nil,
            sleepHoursLastNight: nil,
            stepsSoFar: nil,
            plannedMealCount: plannedMealCount,
            loggedKcalSoFar: 0,
            targetKcal: nil,
            workoutTitle: nil,
            workoutTime: nil
        )
    }

    // MARK: - Interview gate

    private func interviewGate(from context: ModelContext) -> InterviewGate {
        let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first
        if settings?.coachInterviewCompleted == true { return .completed }
        if settings?.coachInterviewSkipped == true { return .skipped }
        return .needsInterview
    }

    private func currentVoiceMode() -> CoachVoiceMode {
        let settings = (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.first
        return settings?.coachVoiceMode ?? .tapToggle
    }
}
