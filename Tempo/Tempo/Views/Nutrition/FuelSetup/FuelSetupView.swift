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
    @Environment(\.tideMood)
    private var mood

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
                            .foregroundStyle(Tide.text)
                        }
                    }
            }
        }
    }

    private var content: some View {
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
        .tidePage()
        .navigationTitle("Fuel setup")
        .navigationBarTitleDisplayMode(.inline)
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
        .tideCovered(openSection != nil)
        .fullScreenCover(isPresented: Binding(
            get: { openSection != nil },
            set: {
                if !$0 {
                    openSection = nil; chain = []
                }
            }
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
                // The presenter sits inside a page; the cover is its own page and needs its own field.
                .environment(\.tideInsidePage, false)
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
            VStack(alignment: .leading, spacing: Tide.s5) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Talk me through your week.")
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Take your time — 2 minutes or 10. The more you tell me, the better your plan.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The voice box is the hero: it comes first, what to cover sits under it.
                VoiceTextField(text: $said, placeholder: String(localized: "Tap the mic and start talking — or type here."), minHeight: 160)
                    .accessibilityIdentifier("fuelSetupSaid")
                if let blocker {
                    AIBlockerCard(blocker: blocker) {
                        self.blocker = nil
                        extract(said)
                    }
                } else if let errorMessage {
                    FuelBanner(icon: "exclamationmark.triangle.fill", tint: Tide.warn, title: errorMessage)
                }
                promptList
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s6)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .fuelBottomBar {
            VStack(spacing: Tide.s1) {
                Button {
                    extract(said)
                } label: {
                    Text("Build my profile")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tidePrimary)
                .disabled(said.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                .accessibilityIdentifier("fuelSetupBuild")
                Button {
                    step = .review
                } label: {
                    Text("Fill it in myself")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuelSetupManual")
            }
        }
    }

    /// What worth saying, one idea per line with its own symbol.
    private var promptList: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: String(localized: "Worth mentioning"))
                .padding(.horizontal, Tide.s1)
            VStack(alignment: .leading, spacing: Tide.s3) {
                ForEach(Array(Self.prompts.enumerated()), id: \.offset) { index, prompt in
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                        Image(systemName: Self.promptIcons[index % Self.promptIcons.count])
                            .font(Tide.bodyStrong)
                            .foregroundStyle(mood.accent)
                            .frame(width: Tide.icon, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(prompt)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private static let promptIcons = [
        "figure.stand", "leaf.fill", "clock.fill", "calendar", "fork.knife", "cart.fill",
    ]

    static var prompts: [String] {
        [
            String(localized: "Age, height, weight — and your goal"),
            String(localized: "What you won't eat, allergies, foods you love"),
            String(localized: "Each day: wake up, leave home, get back, bed"),
            String(localized: "Classes, work, training — days and times"),
            String(localized: "Where you eat out and with whom (e.g. Panera at campus, 1 pm)"),
            String(localized: "How much you cook, budget, where you shop"),
        ]
    }

    // MARK: - Thinking

    private var thinkingStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                Text("Building your profile…")
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                FuelAIState(kind: .working(String(localized: "Reading what you said and filling in the sections.")))
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
        }
        .scrollDisabled(true)
    }

    // MARK: - Follow-ups

    private func followUpStep(_ questions: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                Text("A few more things.")
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    VStack(alignment: .leading, spacing: Tide.s3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(index + 1) of \(questions.count)").tideLabel(mood.accent)
                            Spacer(minLength: Tide.s2)
                            if !(answers[question] ?? "").isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(Tide.bodyStrong)
                                    .foregroundStyle(Tide.good)
                                    .transition(.scale.combined(with: .opacity))
                                    .accessibilityLabel("Answered")
                            }
                        }
                        .animation(Tide.snap, value: (answers[question] ?? "").isEmpty)
                        Text(question)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        VoiceTextField(
                            text: Binding(get: { answers[question] ?? "" }, set: { answers[question] = $0 }),
                            placeholder: String(localized: "Answer…"),
                            minHeight: 56
                        )
                        .accessibilityIdentifier("fuelSetupAnswer\(index)")
                    }
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s6)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .fuelBottomBar {
            VStack(spacing: Tide.s1) {
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
                .buttonStyle(.tidePrimary)
                .accessibilityIdentifier("fuelSetupContinue")
                Button {
                    step = .review
                } label: {
                    Text("Skip — I'll check it myself")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
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
            return String(localized: "Save and continue")
        }
        guard hasUnsavedSections else {
            return nil
        }
        if !isFirstTime {
            return String(localized: "Save changes (\(unsavedSections.count))")
        }
        return draft.isComplete ? String(localized: "Save my profile") : String(localized: "Save what I have")
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
    @FocusState
    private var focused: Bool
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(alignment: .trailing, spacing: Tide.s2) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .focused($focused)
                .lineLimit(3 ... 40)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .padding(Tide.s4)
                .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
                // The whole box takes a tap, not just the first line.
                .contentShape(.rect(cornerRadius: Tide.tileRadius))
                .onTapGesture { focused = true }
                .disabled(transcriber.isListening)
            HStack(spacing: Tide.s2) {
                if let error = transcriber.error {
                    Text(error)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if transcriber.isListening {
                    Text("Listening… tap to stop")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                Button(action: toggle) {
                    Image(systemName: transcriber.isListening ? "stop.fill" : "mic.fill")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.ink)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Tide.hit + Tide.s1, height: Tide.hit + Tide.s1)
                        .background(transcriber.isListening ? Tide.danger : mood.accent, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .animation(Tide.snap, value: transcriber.isListening)
                .accessibilityLabel(transcriber.isListening ? String(localized: "Stop listening") : String(localized: "Talk"))
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
