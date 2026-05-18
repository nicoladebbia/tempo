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
    /// Low-confidence fallback: dismiss and open the Search tab pre-filled.
    var onSearchInstead: ((String) -> Void)?

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
    }

    @State private var phase: Phase = .idle
    @State private var questions: [VoiceClarifyingQuestion] = []
    @State private var questionIndex = 0
    @State private var answers: [String: String] = [:]
    @State private var resolved: [VoiceResolvedItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.xl) {
                switch phase {
                case .idle, .recording:
                    micSection
                case .thinking:
                    thinkingSection
                case .clarifying:
                    clarifyingSection
                case .confirming:
                    confirmationSection
                case let .failed(message):
                    failureSection(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(TempoSpacing.screenEdge)
            .background(Color.tempoBgPrimary)
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
        VStack(spacing: TempoSpacing.xl) {
            Spacer()

            Text(transcriber.isListening
                ? "Listening… describe your meal"
                : "Tap the mic and say what you ate")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: transcriber.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.tempoTextInverse)
                    .frame(width: 96, height: 96)
                    .background(transcriber.isListening ? Color.tempoError : Color.tempoSignal)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            if !transcriber.transcribedText.isEmpty {
                Text(transcriber.transcribedText)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(TempoSpacing.cardPadding)
                    .frame(maxWidth: .infinity)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            }

            if let err = transcriber.error {
                Text(err)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoError)
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
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Reading your meal…")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
        }
    }

    private func runExtraction() async {
        guard let service else { return }
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
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Clarifying (one question at a time, tappable answers only)

    private var clarifyingSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Text("Question \(questionIndex + 1) of \(questions.count)")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)

            if questionIndex < questions.count {
                let q = questions[questionIndex]
                Text(q.question)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)

                ForEach(q.options.prefix(4), id: \.self) { option in
                    Button {
                        answers[q.question] = option
                        advanceQuestion()
                    } label: {
                        Text(option)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(TempoSpacing.md)
                            .background(Color.tempoSurfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.tempoBorder, lineWidth: 1)
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
        guard let service else { return }
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
            phase = .failed(error.localizedDescription)
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("Confirm your meal")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)

            ScrollView {
                VStack(spacing: TempoSpacing.sm) {
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
            .buttonStyle(.tempoPrimary)
        }
    }

    private func resolvedRow(_ item: VoiceResolvedItem) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                Text(item.name)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if item.isLowConfidence {
                    Text("Low confidence")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoWarning)
                }
            }

            Text("\(Int(item.quantityG)) g · \(Int(item.calories)) kcal · "
                + "P \(Int(item.proteinG)) / C \(Int(item.carbsG)) / F \(Int(item.fatG))")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            if item.isLowConfidence {
                Button {
                    transcriber.stop()
                    dismiss()
                    onSearchInstead?(item.name)
                } label: {
                    Text("Search instead")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoSignal)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func logResolvedItems() {
        for item in resolved where !item.isLowConfidence {
            let food = FoodItem(
                id: UUID(),
                name: item.name,
                brand: nil,
                servingSize: "\(Int(item.quantityG)) g",
                servingQuantity: item.quantityG,
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

    private func failureSection(_ message: String) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.tempoWarning)
            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            Button {
                // transcriber.start() clears transcribedText itself.
                phase = .idle
            } label: {
                Text("Try again")
            }
            .buttonStyle(.tempoPrimary)
            Spacer()
        }
    }
}
