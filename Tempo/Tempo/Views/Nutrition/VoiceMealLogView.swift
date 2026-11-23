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
                    .frame(width: 96, height: 96)
                    .background(transcriber.isListening ? Tide.danger : mood.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            if !transcriber.transcribedText.isEmpty {
                Text(transcriber.transcribedText)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .padding(Tide.s4)
                    .frame(maxWidth: .infinity)
                    .background(Tide.fill)
                    .clipShape(RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous))
            }

            if let err = transcriber.error {
                Text(err)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
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
            ProgressView()
                .controlSize(.large)
            Text("Reading your meal…")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
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
            Text("Question \(questionIndex + 1) of \(questions.count)")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)

            if questionIndex < questions.count {
                let q = questions[questionIndex]
                Text(q.question)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)

                ForEach(q.options.prefix(4), id: \.self) { option in
                    Button {
                        answers[q.question] = option
                        advanceQuestion()
                    } label: {
                        Text(option)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Tide.s3)
                            .background(Tide.fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Tide.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
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
                ? .failed("No food items found.")
                : .confirming
        } catch {
            phase = AIBlocker(error).map(Phase.blocked) ?? .failed(AIBlocker.readableDescription(error))
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Confirm your meal")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)

            ScrollView {
                VStack(spacing: Tide.s2) {
                    ForEach(Array(resolved.enumerated()), id: \.offset) { _, item in
                        resolvedRow(item)
                    }
                }
            }

            Button {
                logResolvedItems()
            } label: {
                Text("Log it")
            }
            .buttonStyle(.tidePrimary)
        }
    }

    private func resolvedRow(_ item: VoiceResolvedItem) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack {
                Text(item.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Spacer()
                if item.isLowConfidence {
                    Text("Low confidence")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.warn)
                }
            }

            Text("\(Int(item.quantityG)) g · \(Int(item.calories)) kcal · "
                + "P \(Int(item.proteinG)) / C \(Int(item.carbsG)) / F \(Int(item.fatG))")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)

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
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Tide.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tide.fill)
        .clipShape(RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous))
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
        VStack(spacing: Tide.s4) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(Tide.title)
                .foregroundStyle(Tide.warn)
            Text(message)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
            Button {
                // transcriber.start() clears transcribedText itself.
                phase = .idle
            } label: {
                Text("Try again")
            }
            .buttonStyle(.tidePrimary)
            Spacer()
        }
    }
}
