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
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: transcriber.isListening ? "stop.fill" : "mic.fill")
                    .font(Tide.largeTitle)
                    .foregroundStyle(Tide.ink)
                    .frame(width: Tide.Kitchen.verdictDial, height: Tide.Kitchen.verdictDial)
                    .glassEffect(
                        .regular.tint(transcriber.isListening ? Tide.danger : mood.accent).interactive(),
                        in: .circle
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .background {
                        KitchenListeningRing(active: transcriber.isListening, tint: Tide.danger)
                    }
            }
            .buttonStyle(.plain)
            .padding(.vertical, Tide.s6)
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
                KitchenNotice(systemImage: "exclamationmark.triangle.fill", text: err, tint: Tide.danger)
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
            TideSectionLabel(title: "Confirm these changes", trailing: "\(intents.count) to apply")
            Text("Nothing has been changed yet.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)

            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    ForEach(Array(intents.enumerated()), id: \.offset) { _, intent in
                        HStack(spacing: Tide.s3) {
                            Image(systemName: icon(for: intent))
                                .font(Tide.bodyStrong)
                                .foregroundStyle(tint(for: intent))
                                .frame(width: Tide.Kitchen.tile, height: Tide.Kitchen.tile)
                                .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
                                .accessibilityHidden(true)
                            Text(describe(intent))
                                .font(Tide.headline)
                                .foregroundStyle(Tide.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
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

    private func tint(for intent: PantryEditIntent) -> Color {
        if case .discard = intent {
            return Tide.danger
        }
        return mood.accent
    }

    private func icon(for intent: PantryEditIntent) -> String {
        switch intent {
        case .markDepleted: "cart.badge.plus"
        case .decrement: "minus.circle"
        case .move: "arrow.right.circle"
        case .discard: "trash"
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
            KitchenHeroDisc(systemImage: "checkmark.circle.fill", tint: Tide.Kitchen.good)
                .symbolEffect(.bounce, value: appliedSummaries.count)
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
            .padding(.top, Tide.s2)
            Spacer()
        }
    }

    // MARK: - Failure

    private func failureSection(_ message: String) -> some View {
        VStack {
            Spacer()
            KitchenFailure(
                title: "That didn't work",
                message: message,
                retry: { phase = .idle }
            )
            Spacer()
        }
    }
}
