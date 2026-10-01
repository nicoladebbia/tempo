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
            VStack(spacing: TempoSpacing.xl) {
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
            .padding(TempoSpacing.screenEdge)
            .background(Color.tempoBgPrimary)
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
        VStack(spacing: TempoSpacing.xl) {
            Spacer()
            Text(transcriber.isListening
                ? "Listening… say what changed, then tap stop"
                : "\"I'm out of rice\", \"I used half the chicken\", \"move the salmon to the freezer\"")
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
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("Confirm these changes")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Nothing has been changed yet.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)

            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    ForEach(Array(intents.enumerated()), id: \.offset) { _, intent in
                        Text(describe(intent))
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .padding(TempoSpacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.tempoSurfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    }
                }
            }

            Button {
                applyIntents()
            } label: {
                Text("Apply \(intents.count) change\(intents.count == 1 ? "" : "s")")
            }
            .buttonStyle(.tempoPrimary)
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
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoSuccess)
            ForEach(appliedSummaries, id: \.self) { summary in
                Text(summary)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("Done") {
                transcriber.stop()
                dismiss()
            }
            .buttonStyle(.tempoPrimary)
            Spacer()
        }
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
            Button("Try again") {
                phase = .idle
            }
            .buttonStyle(.tempoPrimary)
            Spacer()
        }
    }
}
