//
// VoiceMealLogView.swift
// Tempo
//
// AI voice meal logging. Drives the existing VoiceTranscriber, sends the
// transcript to Claude Haiku for item extraction + multiple-choice
// clarifications, then shows a confirmation card before the resolved items
// are handed back to MealLoggingView (which persists them to MealLog).
//

import SwiftUI

struct VoiceMealLogView: View {
    /// Called once per confirmed item, mirroring FoodSearchView.onFoodSelected
    /// so the existing MealLogging save path is reused unchanged.
    var onFoodSelected: ((FoodItem) -> Void)?
    /// The eat time the user said ("at 1pm"), when the model resolved one, so
    /// the log lands at that time instead of "now".
    var onEatTime: ((Date) -> Void)?
    /// Low-confidence fallback: dismiss and open the Search tab pre-filled.
    var onSearchInstead: ((String) -> Void)?

    @Environment(\.tideMood)
    private var mood
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dismiss)
    private var dismiss

    @State private var transcriber = VoiceTranscriber()
    @State private var service: VoiceMealLogService?

    private enum Phase: Equatable {
        case idle
        case recording
        case thinking
        case clarifying
        case confirming
        case failed(String)
        /// Pro / AI-off: the card offers the fix.
        case blocked(AIBlocker)
    }

    private static let noFoodMessage = "No food items found."

    @State private var phase: Phase = .idle
    @State private var questions: [VoiceClarifyingQuestion] = []
    @State private var questionIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var resolved: [VoiceResolvedItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: Tide.s5) {
                switch phase {
                case .idle,
                     .recording:
                    micSection
                case .thinking:
                    thinkingSection
                case .clarifying:
                    clarifyingSection
                case .confirming:
                    confirmationSection
                case let .failed(message):
                    failureSection(message)
                case let .blocked(blocker):
                    blockedSection(blocker) { Task { await runExtraction() } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(Tide.edge)
            // The one action sits under the thumb once there is something to log.
            .fuelBottomBar(isShown: phase == .confirming) {
                Button("Log it") { logResolvedItems() }
                    .buttonStyle(.tidePrimary)
            }
            .animation(Tide.settle, value: phase)
            .tidePage()
            .navigationTitle("Voice Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        transcriber.stop()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if service == nil {
                service = VoiceMealLogService(apiClient: services.apiClient)
            }
            transcriber.silenceTimeout = 3.0
        }
        .onChange(of: transcriber.isListening) { wasListening, nowListening in
            // Auto-stop (3s silence) or manual stop ends recording → extract.
            if wasListening, !nowListening, phase == .recording {
                Task { await runExtraction() }
            }
        }
    }

    // MARK: - Mic

    private var micSection: some View {
        VStack(spacing: Tide.s5) {
            Spacer()

            Text(transcriber.isListening
                ? "Listening… describe your meal"
                : "Tap the mic and say what you ate")
                .font(Tide.headline)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)

            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: transcriber.isListening ? "stop.fill" : "mic.fill")
                    .font(Tide.title)
                    .foregroundStyle(Tide.ink)
                    .symbolEffect(.pulse, isActive: transcriber.isListening)
                    .frame(width: Tide.fuelMic, height: Tide.fuelMic)
                    .background(transcriber.isListening ? Tide.danger : mood.accent, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(FuelPressStyle())
            .animation(Tide.snap, value: transcriber.isListening)
            .accessibilityLabel(transcriber.isListening ? "Stop recording" : "Start recording")

            if !transcriber.transcribedText.isEmpty {
                Text(transcriber.transcribedText)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                    .transition(.opacity)
            }

            if let err = transcriber.error {
                Text(err)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private func toggleRecording() async {
        if transcriber.isListening {
            transcriber.stop() // onChange triggers extraction
        } else {
            phase = .recording
            await transcriber.start()
            if transcriber.error != nil {
                phase = .idle
            }
        }
    }

    // MARK: - Thinking

    private var thinkingSection: some View {
        VStack(spacing: Tide.s4) {
            Spacer()
            FuelAIState(kind: .working("Reading your meal…"))
            Spacer()
        }
    }

    private func runExtraction() async {
        guard let service else {
            return
        }
        let transcript = transcriber.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            phase = .idle
            return
        }
        phase = .thinking
        do {
            questions = try await service.extract(transcript: transcript)
            questionIndex = 0
            answers = [:]
            if questions.isEmpty {
                await runResolve()
            } else {
                phase = .clarifying
            }
        } catch {
            phase = AIBlocker(error).map(Phase.blocked) ?? .failed(AIBlocker.readableDescription(error))
        }
    }

    // MARK: - Clarifying (one question at a time, tappable answers only)

    private var clarifyingSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Question \(questionIndex + 1) of \(questions.count)")

            if questionIndex < questions.count {
                let q = questions[questionIndex]
                Text(q.question)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(q.options.prefix(4), id: \.self) { option in
                    Button {
                        HapticManager.lightImpact()
                        answers[q.question] = option
                        advanceQuestion()
                    } label: {
                        Text(option)
                            .font(Tide.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Tide.s4)
                            .fuelChoice(selected: false, minHeight: Tide.hit + Tide.s3)
                    }
                    .buttonStyle(FuelPressStyle())
                }
            }

            Spacer()
        }
    }

    private func advanceQuestion() {
        if questionIndex + 1 < questions.count {
            questionIndex += 1
        } else {
            Task { await runResolve() }
        }
    }

    // MARK: - Resolve + Confirmation

    private func runResolve() async {
        guard let service else {
            return
        }
        phase = .thinking
        do {
            resolved = try await service.resolve(
                transcript: transcriber.transcribedText,
                answers: answers
            )
            phase = resolved.isEmpty
                ? .failed(Self.noFoodMessage)
                : .confirming
        } catch {
            phase = AIBlocker(error).map(Phase.blocked) ?? .failed(AIBlocker.readableDescription(error))
        }
    }

    private var confirmationSection: some View {
        // What will be logged: the confident items only, so the number matches
        // the Confirm Meal sheet the user lands on next.
        let kcal = resolved.filter { !$0.isLowConfidence }.reduce(0) { $0 + Int($1.calories) }
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(
                title: "Confirm your meal",
                trailing: FuelWords.count(resolved.count, "item")
            )
            TideNumber("\(kcal)", unit: "kcal", size: Tide.numeralL)

            ScrollView {
                VStack(spacing: Tide.s2) {
                    ForEach(Array(resolved.enumerated()), id: \.offset) { _, item in
                        resolvedRow(item)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func resolvedRow(_ item: VoiceResolvedItem) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(item.name)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tide.s2)
                if item.isLowConfidence {
                    FuelPill(text: "Low confidence", color: Tide.warn)
                }
            }

            Text("\(Int(item.quantityG)) g · \(Int(item.calories)) kcal · "
                + "P \(Int(item.proteinG)) / C \(Int(item.carbsG)) / F \(Int(item.fatG))")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            if item.isLowConfidence {
                Button {
                    transcriber.stop()
                    dismiss()
                    onSearchInstead?(item.name)
                } label: {
                    Text("Search instead")
                        .font(Tide.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(mood.accent)
                        .frame(minHeight: Tide.hit, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private func logResolvedItems() {
        let confident = resolved.filter { !$0.isLowConfidence }
        if let eatTime = confident.earliestLoggedAt {
            onEatTime?(eatTime)
        }
        for item in confident {
            // One serving of the resolved portion: the kcal/macros already
            // cover the whole "<n> g". (quantity was the gram count before —
            // 250 servings of "250 g" — which inflated the logged grams.)
            let food = FoodItem(
                id: UUID(),
                name: item.name,
                brand: nil,
                servingSize: "\(Int(item.quantityG)) g",
                servingQuantity: 1,
                calories: Int(item.calories),
                protein: item.proteinG,
                carbs: item.carbsG,
                fat: item.fatG
            )
            onFoodSelected?(food)
        }
        dismiss()
    }

    // MARK: - Failure

    private func blockedSection(_ blocker: AIBlocker, retry: @escaping () -> Void) -> some View {
        VStack(spacing: Tide.s4) {
            Spacer()
            AIBlockerCard(blocker: blocker, onConsentGranted: retry)
            Spacer()
        }
    }

    private func failureSection(_ message: String) -> some View {
        // transcriber.start() clears transcribedText itself.
        let retry = { phase = .idle }
        return VStack(spacing: Tide.s4) {
            Spacer()
            if message == Self.noFoodMessage {
                FuelAIState(
                    kind: .empty(
                        title: "No food found",
                        message: "Nothing in that sounded like food. Say what was on the plate, with amounts if you can."
                    ),
                    actionTitle: "Try again", action: retry
                )
            } else {
                FuelAIState(
                    kind: .failed(title: "Couldn't read that", message: message),
                    actionTitle: "Try again", action: retry
                )
            }
            Spacer()
        }
    }
}
