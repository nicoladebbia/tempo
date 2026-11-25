//
// CoachChat.swift
// Tempo
//
// The one way into the Coach chat. Present it from anywhere (a sheet, a
// navigation push, a tab): it builds everything the chat needs from the app's
// services, so the caller passes nothing.
//
//     .sheet(isPresented: $showAsk) { CoachChat() }
//
// It owns the `CoachViewModel`, assembles the agent loop's adapters from the
// shared `APIClient`, and builds the system prompt fresh on every send so
// today's live state and the learned preferences are never stale.
//
// The interview, memory and history screens that used to sit around the chat
// are gone; the chat, its view model, the services and the backend calls stay.
//

import SwiftData
import SwiftUI

// MARK: - CoachChat

struct CoachChat: View {
    /// Optional sleep reader for the OutcomeEvidenceProvider. The default
    /// reads nothing, so bedtime grading falls back to "unclear".
    var sleepReader: HKSleepReader = NoopHKSleepReader()
    /// Override for tests and previews. nil uses the real voice transcriber.
    var voiceOverride: (any CoachVoiceControlling)?

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var viewModel: CoachViewModel?

    var body: some View {
        Group {
            if let viewModel {
                CoachChatView(
                    viewModel: viewModel,
                    systemPromptBuilder: { buildSystemPrompt() },
                    emptyStateSeeds: Self.askSeeds,
                    voice: voiceOverride ?? CoachVoiceController(),
                    voiceMode: currentVoiceMode(),
                    title: String(localized: "Ask Tempo")
                )
            } else {
                TideCoachSkeleton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tidePage(energy: 1)
        .task {
            bootstrapViewModelIfNeeded()
        }
    }

    // MARK: - Bootstrap

    private func bootstrapViewModelIfNeeded() {
        guard viewModel == nil else {
            return
        }

        // The agent loop's adapters share the app's auth and retry
        // infrastructure through the one APIClient.
        let apiClient = services.apiClient
        let chatClient = CoachChatAIClientAdapter(requester: apiClient)
        let summarizer = ConversationSummarizerAIClientAdapter(requester: apiClient)
        let dispatcher = CoachToolDispatcherAdapter(
            conversationID: UUID(), // overridden per-conversation by Phase 6b
            turnIndex: 0,
            outcomeEnv: { [notifications = services.notifications, whoop = services.whoop] context in
                MealOutcomeService.Env.live(modelContext: context, notifications: notifications, whoop: whoop)
            }
        )
        let service = CoachService(
            aiClient: chatClient,
            summarizerClient: summarizer,
            toolDispatcher: dispatcher
        )
        let vm = CoachViewModel(
            service: service,
            extractorClient: PreferenceExtractorAdapter(requester: apiClient)
        )
        vm.loadOrStartConversation(context: modelContext)
        viewModel = vm

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
            calendarEvents: [],
            recentConversationSummaries: []
        )
        return snapshot.render()
    }

    /// What the chat opens with when nothing has been said yet: questions
    /// about the day, not commands.
    static let askSeeds = [
        String(localized: "What should I eat next?"),
        String(localized: "Should I train hard today?"),
        String(localized: "How is my week going?"),
    ]

    /// Live-state snapshot for today: the meals planned and their timing, and
    /// the same recovery, sleep, steps, calories and session Today shows (read
    /// from the copy Today saves, so the chat and the screen never disagree).
    private func liveSnapshot() -> TodayLiveSnapshot {
        let now = Date()
        let todayMeals = CanonicalMeals.meals(on: now, in: modelContext)
        // Per-meal planned vs actual timing rows, sorted by mealNumber so
        // Coach reads breakfast, lunch, dinner.
        let timings = todayMeals
            .sorted { $0.mealNumber < $1.mealNumber }
            .compactMap(PlannedMealTimingEntry.from(_:))
        let today = TodayCache.shared.load(now: now, calendar: .current)
        let recovery = today?.recovery
        let workout = today?.workout
        let hasWorkout = workout.map { $0.status == .planned || $0.status == .completed } ?? false
        var snapshot = TodayLiveSnapshot(
            date: now,
            dayType: workout?.status == .rest ? .rest : nil,
            recoveryScore: recovery?.score.map(Double.init),
            recoveryZone: recovery?.score.map { RecoveryZone(score: Double($0)).rawValue },
            hrvMs: recovery?.hrv.map(Double.init),
            restingHR: recovery?.restingHR.map(Double.init),
            sleepHoursLastNight: recovery?.sleepHours,
            stepsSoFar: today?.steps,
            plannedMealCount: todayMeals.count,
            loggedKcalSoFar: today?.fuel.calories ?? 0,
            targetKcal: today?.fuel.calorieTarget,
            workoutTitle: hasWorkout ? workout?.name : nil,
            workoutTime: nil
        )
        snapshot.mealTimings = timings
        return snapshot
    }

    private func currentVoiceMode() -> CoachVoiceMode {
        let settings = (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.first
        return settings?.coachVoiceMode ?? .tapToggle
    }
}
