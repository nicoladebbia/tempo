//
// FuelSetupView.swift
// Tempo
//
// The single nutrition onboarding. Talk (as long as you like) or type about
// your body, goal, food and your week → AI fills the profile → a few
// follow-ups for what's missing → the overview of section cards. Each card
// opens its own onboarding-style flow and saves only that section; the first
// time, "Save my profile" stores everything at once; afterwards a sticky
// "Save changes (n)" bar appears whenever anything is unsaved. "Finish setup"
// chains through the sections still missing (required first), saving each as
// it goes. The overview doubles as the manual path (no Pro / offline) and as
// the Settings editor. Body stats Apple Health supplies are read-only. Every
// Sunday the weekly planner reads what's saved here.
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
    /// "Finish setup": the sections still to walk through, in order (empty = a single edit).
    @State
    private var chain: [FuelSetupSection] = []
    /// Keeps the flow's content alive while the cover slides away.
    @State
    private var lastOpenSection: FuelSetupSection?
    /// Optional sections already saved or skipped (kept on the device).
    @State
    private var reviewed: Set<FuelSetupSection> = []
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
    private var showDiscardConfirm = false
    @State
    private var showNeedsBodyAlert = false
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
                            Button("Cancel") {
                                if hasUnsavedSections {
                                    showDiscardConfirm = true
                                } else {
                                    dismiss()
                                }
                            }
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
                        reviewed: reviewed,
                        primaryActionTitle: primaryActionTitle,
                        blockedMessage: onSaveAndGenerate == nil ? nil : draft.requiredMissingMessage,
                        onOpen: { openSection = $0 },
                        onFinish: startChain,
                        onSkip: skipOnCard,
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
        .interactiveDismissDisabled(!embedded && hasUnsavedSections)
        .confirmationDialog("Discard unsaved changes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Some sections have changes you haven't saved.")
        }
        .alert("Body and goal first", isPresented: $showNeedsBodyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add your weight, height, age, sex and goal. Food and cooking answers stay here until then.")
        }
        .fullScreenCover(isPresented: Binding(
            get: { openSection != nil },
            set: { if !$0 { openSection = nil; chain = [] } }
        )) {
            // One presentation for the whole chain: the section swaps inside it.
            if let section = openSection ?? lastOpenSection {
                NavigationStack {
                    FuelSetupSectionFlow(
                    section: section,
                    draft: draft,
                    locked: healthLocked,
                    unit: settings.first?.weightUnit ?? .kg,
                    isChain: !chain.isEmpty,
                    chainNext: FuelSetupDraft.next(after: section, in: chain),
                    onSkipSection: { skipInChain(section) },
                    onSave: { edited in await saveSection(section, edited) },
                    onClose: { openSection = nil; chain = [] }
                )
                    .id(section)
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .onChange(of: openSection) { _, new in
            if let new {
                lastOpenSection = new
            }
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            reviewed = FuelSetupProgress.reviewed()
            draft = FuelSetupDraft.load(from: modelContext)
            saved = draft
            isFirstTime = UserDailyPlanProfile.current(in: modelContext)?.weeklyRoutine == nil
                && (try? modelContext.fetchCount(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true }))) == 0
            // Someone who already set things up lands on the editor.
            if startInReview || (!isFirstTime && draft.goal != nil) {
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

    /// The sticky bar's title: "Save changes (n)" whenever something is
    /// unsaved, "Save my profile" the first time, "Save and continue" when
    /// saving also builds the plan. nil (hidden) when there is nothing to save.
    private var primaryActionTitle: String? {
        if onSaveAndGenerate != nil {
            return "Save and continue"
        }
        guard hasUnsavedSections else {
            return nil
        }
        if !isFirstTime {
            return "Save changes (\(unsavedSections.count))"
        }
        return draft.isComplete ? "Save my profile" : "Save what I have"
    }

    private var unsavedSections: [FuelSetupSection] {
        FuelSetupSection.allCases.filter { draft.isDirty($0, comparedTo: saved) }
    }

    private var hasUnsavedSections: Bool {
        !unsavedSections.isEmpty
    }

    /// "Finish setup" / "Finish what's missing": opens the first section, the
    /// rest follow one after another.
    private func startChain(_ sections: [FuelSetupSection]) {
        guard let first = sections.first else {
            return
        }
        chain = sections
        openSection = first
    }

    /// "Optional · Skip" on an overview card: stop offering it.
    private func skipOnCard(_ section: FuelSetupSection) {
        FuelSetupProgress.markReviewed(section)
        reviewed.insert(section)
    }

    /// "Skip section" in a chain: next section, or done.
    private func skipInChain(_ section: FuelSetupSection) {
        skipOnCard(section)
        openSection = FuelSetupDraft.next(after: section, in: chain)
        if openSection == nil {
            chain = []
        }
    }

    private func save() {
        let stored = draft.save(to: modelContext)
        for section in stored {
            saved.copy(section, from: draft)
        }
        HapticManager.success()
        registerNotificationsOnce()
        if stored.count < FuelSetupSection.allCases.count {
            // Body/goal answers are missing, so Food/Cooking couldn't be stored:
            // stay here with them intact instead of losing them.
            showNeedsBodyAlert = true
            return
        }
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
        let stored = draft.save(sections: [section], to: modelContext)
        for done in stored {
            saved.copy(done, from: draft)
        }
        isFirstTime = UserDailyPlanProfile.current(in: modelContext)?.weeklyRoutine == nil
            && (try? modelContext.fetchCount(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true }))) == 0
        HapticManager.success()
        registerNotificationsOnce()
        FuelSetupProgress.markReviewed(section)
        reviewed.insert(section)
        // In a chain the next section opens (Goal can store the body answers
        // You couldn't yet); at the end, anything still unstored gets the alert.
        if let next = FuelSetupDraft.next(after: section, in: chain) {
            openSection = next
            return
        }
        chain = []
        openSection = nil
        if !stored.contains(section) {
            showNeedsBodyAlert = true
        }
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
        // Only someone who already connected Health is asked again (for the
        // new age and sex types); everyone else just fills the fields in.
        if stats == HealthBodyStats(), UserDefaults.standard.bool(forKey: "healthKitAuthorized") {
            try? await services.healthKit.requestAuthorization()
            let body = try? await services.healthKit.fetchBodyComposition()
            let traits = await services.healthKit.fetchProfileCharacteristics()
            stats = HealthBodyStats(body: body, characteristics: traits)
        }
        health = stats
        // Only fields the user hasn't edited meanwhile: a slow fetch must not
        // overwrite typed values.
        healthLocked = draft.apply(health: stats, untouchedSince: saved)
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
