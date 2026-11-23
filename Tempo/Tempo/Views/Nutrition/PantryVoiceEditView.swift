//
// PantryVoiceEditView.swift
// Tempo
//
// Voice EDITS to an already-stocked pantry — "I'm out of rice", "I used
// half the chicken", "move the salmon to the freezer", "throw out the
// spinach". Separate from VoicePantryView (which ADDS/SETS stock from a
// stock-take): this is a rule-based, offline parse
// (`VoicePantryEditParser`) with no AI round-trip, mirroring the mic UI
// but skipping the "thinking" network phase entirely.
//

import SwiftData
import SwiftUI

struct PantryVoiceEditView: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    @State private var transcriber = VoiceTranscriber()

    private enum Phase: Equatable {
        case idle
        case recording
        case confirming
        case applied
        case failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var intents: [PantryEditIntent] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: Tide.s5) {
                switch phase {
                case .idle,
                     .recording:
                    micSection
                case .confirming:
                    confirmSection
                case .applied:
                    appliedSection
                case let .failed(message):
                    failureSection(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(Tide.edge)
            .kitchenPage()
            .navigationTitle("Pantry Voice Edit")
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
            transcriber.silenceTimeout = 0
            transcriber.continuousMode = true
        }
        .onChange(of: transcriber.isListening) { wasListening, nowListening in
            if wasListening, !nowListening, phase == .recording {
                runParse(transcriber.transcribedText)
            }
        }
    }

    // MARK: - Mic

    private var micSection: some View {
        VStack(spacing: Tide.s5) {
            Spacer()
            Text(transcriber.isListening
                ? "Listening… say what changed, then tap stop"
                : "\"I'm out of rice\", \"I used half the chicken\", \"move the salmon to the freezer\"")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)

            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: transcriber.isListening ? "stop.fill" : "mic.fill")
                    .font(Tide.largeTitle)
                    .foregroundStyle(Tide.ink)
                    .frame(width: 112, height: 112)
                    .glassEffect(
                        .regular.tint(transcriber.isListening ? Tide.danger : mood.accent).interactive(),
                        in: .circle
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact, trigger: transcriber.isListening)
            .accessibilityLabel(transcriber.isListening ? "Stop listening" : "Start listening")

            if !transcriber.transcribedText.isEmpty {
                Text(transcriber.transcribedText)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .tideCard(padding: Tide.s4)
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
            transcriber.stop()
        } else {
            phase = .recording
            await transcriber.start()
            if transcriber.error != nil {
                phase = .idle
            }
        }
    }

    private func runParse(_ rawTranscript: String) {
        let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            phase = .failed("I didn't catch anything. Tap the mic and try again.")
            return
        }
        let parsed = VoicePantryEditParser.parse(transcript)
        guard !parsed.isEmpty else {
            phase = .failed("Didn't recognize an edit in that. Try \"I'm out of X\" or \"move X to the freezer\".")
            return
        }
        intents = parsed
        phase = .confirming
    }

    // MARK: - Confirm (shown BEFORE anything is applied)

    private var confirmSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Confirm these changes")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            Text("Nothing has been changed yet.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)

            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    ForEach(Array(intents.enumerated()), id: \.offset) { _, intent in
                        Text(describe(intent))
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button {
                applyIntents()
            } label: {
                Text("Apply \(intents.count) change\(intents.count == 1 ? "" : "s")")
            }
            .buttonStyle(.tidePrimary)
        }
    }

    private func describe(_ intent: PantryEditIntent) -> String {
        switch intent {
        case let .markDepleted(rawName):
            "Mark \(rawName) as out, add to grocery list"
        case let .decrement(rawName, fraction):
            fraction >= 1 ? "Used up \(rawName)" : "Used half of \(rawName)"
        case let .move(rawName, location):
            "Move \(rawName) to the \(location.rawValue)"
        case let .discard(rawName):
            "Throw out \(rawName)"
        }
    }

    private func applyIntents() {
        guard let service = viewModel.pantryService else {
            phase = .failed("Pantry isn't ready yet.")
            return
        }
        let results = VoicePantryEditApplier.apply(intents, pantryService: service, modelContext: modelContext)
        appliedSummaries = results.map(\.summary)
        viewModel.reloadPantry()
        viewModel.reapplyPantryToGrocery()
        phase = .applied
    }

    @State private var appliedSummaries: [String] = []

    private var appliedSection: some View {
        VStack(spacing: Tide.s4) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(Tide.largeTitle)
                .foregroundStyle(Tide.Kitchen.good)
                .accessibilityHidden(true)
            ForEach(appliedSummaries, id: \.self) { summary in
                Text(summary)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
            }
            Button("Done") {
                transcriber.stop()
                dismiss()
            }
            .buttonStyle(.tidePrimary)
            Spacer()
        }
    }

    // MARK: - Failure

    private func failureSection(_ message: String) -> some View {
        VStack(spacing: Tide.s4) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(Tide.largeTitle)
                .foregroundStyle(Tide.Kitchen.warn)
                .accessibilityHidden(true)
            Text(message)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
            Button("Try again") {
                phase = .idle
            }
            .buttonStyle(.tidePrimary)
            Spacer()
        }
    }
}
