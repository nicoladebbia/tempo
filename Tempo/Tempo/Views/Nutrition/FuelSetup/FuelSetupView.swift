//
// FuelSetupView.swift
// Tempo
//
// The single nutrition onboarding. Talk (as long as you like) or type about
// your body, goal, food and your week → AI fills the profile → a few
// follow-ups for what's missing → the overview of section cards. Each card
// opens its own onboarding-style flow and saves only that section; the first
// time, "Save my profile" stores everything at once. The overview doubles as
// the manual path (no Pro / offline) and as the Settings editor. Body stats
// Apple Health supplies are read-only. Every Sunday the weekly planner reads
// what's saved here.
//

import SwiftData
import SwiftUI

// MARK: - FuelSetupView

struct FuelSetupView: View {
    /// Called after saving with the active profile (e.g. to generate a plan).
    var onSaveAndGenerate: ((DietaryProfile) -> Void)?
    /// Pushed inside an existing navigation stack (Settings) instead of a sheet.
    var embedded = false
    /// "Edit setup" entries: open straight on the review/edit screen, even if
    /// something is still missing, instead of the talk step.
    var startInReview = false

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    private enum Step: Equatable {
        case talk
        case thinking
        case followUps([String])
        case review
    }

    @State
    private var step: Step = .talk
    @State
    private var draft = FuelSetupDraft()
    /// The draft as last stored; the overview flags sections that differ.
    @State
    private var saved = FuelSetupDraft()
    /// Body stats Apple Health supplies (read-only in the editor).
    @State
    private var health = HealthBodyStats()
    @State
    private var healthLocked: Set<FuelBodyField> = []
    @State
    private var openSection: FuelSetupSection?
    @State
    private var hasRequestedPush = false
    @Query
    private var settings: [UserSettings]
    /// Nothing stored yet: the overview offers one "Save my profile".
    @State
    private var isFirstTime = false
    @State
    private var hasLoaded = false
    @State
    private var said = ""
    @State
    private var answers: [String: String] = [:]
    @State
    private var errorMessage: String?
    /// Set when the AI can't run at all (no Pro / AI off) — shows the fix card.
    @State
    private var blocker: AIBlocker?
    /// The in-flight AI call — cancelled if the sheet goes away mid-thought.
    @State
    private var extraction: Task<Void, Never>?

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
            }
        }
    }

    private var content: some View {
        Group {
            Group {
                switch step {
                case .talk:
                    talkStep
                case .thinking:
                    thinkingStep
                case let .followUps(questions):
                    followUpStep(questions)
                case .review:
                    FuelSetupOverviewView(
                        draft: draft,
                        saved: saved,
                        locked: healthLocked,
                        unit: settings.first?.weightUnit ?? .kg,
                        primaryActionTitle: primaryActionTitle,
                        onOpen: { openSection = $0 },
                        onTalkAgain: { step = .talk },
                        onSaveAll: save
                    )
                }
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Fuel setup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .dismissKeyboardOnTapOutside()
        .fullScreenCover(item: $openSection) { section in
            NavigationStack {
                FuelSetupSectionFlow(
                    section: section,
                    draft: draft,
                    locked: healthLocked,
                    unit: settings.first?.weightUnit ?? .kg,
                    onSave: { edited in await saveSection(section, edited) },
                    onClose: { openSection = nil }
                )
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            draft = FuelSetupDraft.load(from: modelContext)
            saved = draft
            isFirstTime = UserDailyPlanProfile.current(in: modelContext)?.weeklyRoutine == nil
                && (try? modelContext.fetchCount(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true }))) == 0
            // Someone who already set things up lands on the editor.
            if startInReview
                || (draft.routine.typicalWakeMinutes != nil && draft.goal != nil
                    && UserDailyPlanProfile.current(in: modelContext)?.weeklyRoutine != nil)
            {
                step = .review
            }
            await fillFromHealth()
        }
        .onDisappear {
            if step == .thinking {
                extraction?.cancel()
            }
        }
    }

    // MARK: - Talk

    private var talkStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text("Talk me through your week.")
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Take your time — 2 minutes or 10. The more you tell me, the better your plan.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                promptList
                VoiceTextField(text: $said, placeholder: "Tap the mic and start talking — or type here.", minHeight: 180)
                    .accessibilityIdentifier("fuelSetupSaid")
                if let blocker {
                    AIBlockerCard(blocker: blocker) {
                        self.blocker = nil
                        extract(said)
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }
                Button {
                    extract(said)
                } label: {
                    Text("Build my profile")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                .disabled(said.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                .accessibilityIdentifier("fuelSetupBuild")
                Button("Fill it in myself") {
                    step = .review
                }
                .buttonStyle(.tempoGhost)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("fuelSetupManual")
            }
            .padding(TempoSpacing.screenEdge)
        }
    }

    private var promptList: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            ForEach(Self.prompts, id: \.self) { prompt in
                Label(prompt, systemImage: "checkmark.circle")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
    }

    static let prompts = [
        "Age, height, weight — and your goal",
        "What you won't eat, allergies, foods you love",
        "Each day: wake up, leave home, get back, bed",
        "Classes, work, training — days and times",
        "Where you eat out and with whom (e.g. Panera at campus, 1 pm)",
        "How much you cook, budget, where you shop",
    ]

    // MARK: - Thinking

    private var thinkingStep: some View {
        VStack(spacing: TempoSpacing.md) {
            ProgressView()
            Text("Building your profile…")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Follow-ups

    private func followUpStep(_ questions: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                Text("A few more things.")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                        Text(question)
                            .font(.tempoBodyBold)
                            .foregroundStyle(Color.tempoTextPrimary)
                        VoiceTextField(
                            text: Binding(get: { answers[question] ?? "" }, set: { answers[question] = $0 }),
                            placeholder: "Answer…",
                            minHeight: 56
                        )
                        .accessibilityIdentifier("fuelSetupAnswer\(index)")
                    }
                }
                Button {
                    let text = questions.compactMap { question in
                        answers[question].flatMap { $0.isEmpty ? nil : "Q: \(question)\nA: \($0)" }
                    }
                    .joined(separator: "\n\n")
                    answers = [:]
                    if text.isEmpty {
                        step = .review
                    } else {
                        extract(text)
                    }
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                .accessibilityIdentifier("fuelSetupContinue")
                Button("Skip — I'll check it myself") {
                    step = .review
                }
                .buttonStyle(.tempoGhost)
                .frame(maxWidth: .infinity)
            }
            .padding(TempoSpacing.screenEdge)
        }
    }

    // MARK: - Actions

    private func extract(_ text: String) {
        errorMessage = nil
        blocker = nil
        step = .thinking
        extraction = Task {
            do {
                let result = try await FuelSetupExtractor.extract(said: text, current: draft, apiClient: services.apiClient)
                guard !Task.isCancelled else {
                    return
                }
                draft = result.draft
                healthLocked = draft.apply(health: health)
                // The AI's questions first, then anything required it didn't ask about.
                var questions = result.followUps
                if questions.count < 5 {
                    questions += draft.missingFields.map(\.question).prefix(5 - questions.count)
                }
                step = questions.isEmpty ? .review : .followUps(questions)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                blocker = AIBlocker(error)
                errorMessage = FuelSetupExtractor.message(for: error)
                step = .talk
            }
        }
    }

    /// First-time "Save my profile": every section at once, then generate.
    private var primaryActionTitle: String? {
        if onSaveAndGenerate != nil {
            return "Save and continue"
        }
        let hasUnsaved = FuelSetupSection.allCases.contains { draft.isDirty($0, comparedTo: saved) }
        return isFirstTime && hasUnsaved ? (draft.isComplete ? "Save my profile" : "Save what I have") : nil
    }

    private func save() {
        draft.save(to: modelContext)
        saved = draft
        HapticManager.success()
        registerNotificationsOnce()
        let profile = (try? modelContext.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first
        dismiss()
        if let profile, let onSaveAndGenerate {
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                onSaveAndGenerate(profile)
            }
        }
    }

    /// Saves ONE section (and nothing else), then returns to the overview.
    private func saveSection(_ section: FuelSetupSection, _ edited: FuelSetupDraft) async {
        var edited = edited
        if section == .week {
            edited.routine = await PlaceLocator.locateMissing(in: edited.routine)
        }
        draft.copy(section, from: edited)
        draft.save(sections: [section], to: modelContext)
        saved.copy(section, from: draft)
        isFirstTime = false
        HapticManager.success()
        registerNotificationsOnce()
        openSection = nil
    }

    /// The routine is what the Sunday plan reads — ask for notifications now
    /// (once) so the Sunday prompt and "plan ready" push can arrive.
    private func registerNotificationsOnce() {
        guard !hasRequestedPush else {
            return
        }
        hasRequestedPush = true
        let pushRegistration = services.pushRegistration
        let notificationSettings = NutritionTabViewModel.loadUserSettings(modelContext: modelContext)
        Task {
            _ = try? await pushRegistration.requestAuthorizationAndRegister()
            await WeeklyPlanReminder.sync(settings: notificationSettings)
        }
    }

    /// Weight, height, body fat, age and sex from the Health app. Whatever
    /// Health has wins and is locked (read-only); only the rest is asked.
    private func fillFromHealth() async {
        var stats = HealthBodyStats()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitesting-fuel-health") {
                stats = HealthBodyStats(weightKg: 82.4, heightCm: 181, age: 24)
            }
        #endif
        if stats == HealthBodyStats() {
            // Asks only for Health types never asked before (age and sex).
            try? await services.healthKit.requestAuthorization()
            let body = try? await services.healthKit.fetchBodyComposition()
            let traits = await services.healthKit.fetchProfileCharacteristics()
            stats = HealthBodyStats(body: body, characteristics: traits)
        }
        health = stats
        healthLocked = draft.apply(health: stats)
    }
}

// MARK: - VoiceTextField

/// A text box with a mic: speech is appended to whatever is typed, with no
/// time limit (continuous dictation until the user taps stop).
struct VoiceTextField: View {
    @Binding
    var text: String
    var placeholder: String
    var minHeight: CGFloat = 80

    @State
    private var transcriber = VoiceTranscriber()
    @State
    private var textBeforeListening = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: TempoSpacing.sm) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(3 ... 40)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .padding(TempoSpacing.md)
                .background(Color.tempoBgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                .disabled(transcriber.isListening)
            HStack(spacing: TempoSpacing.sm) {
                if let error = transcriber.error {
                    Text(error)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }
                Spacer(minLength: 0)
                if transcriber.isListening {
                    Text("Listening… tap to stop")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Button(action: toggle) {
                    Image(systemName: transcriber.isListening ? "stop.fill" : "mic.fill")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextInverse)
                        .frame(width: 48, height: 48)
                        .background(transcriber.isListening ? Color.tempoError : Color.tempoSignal)
                        .clipShape(Circle())
                }
                .accessibilityLabel(transcriber.isListening ? "Stop listening" : "Talk")
            }
        }
        .onChange(of: transcriber.transcribedText) { _, spoken in
            guard transcriber.isListening else {
                return
            }
            text = [textBeforeListening, spoken].filter { !$0.isEmpty }.joined(separator: textBeforeListening.isEmpty ? "" : " ")
        }
        .onDisappear {
            transcriber.stop()
        }
    }

    private func toggle() {
        if transcriber.isListening {
            transcriber.stop()
            return
        }
        textBeforeListening = text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriber.silenceTimeout = 0
        transcriber.continuousMode = true
        HapticManager.lightImpact()
        Task {
            await transcriber.start()
        }
    }
}
