//
// VoicePantryView.swift
// Tempo
//
// AI voice pantry stock-take. Drives the existing VoiceTranscriber, sends the
// transcript to Claude Haiku for item extraction + multiple-choice
// clarifications, then shows a confirmation card before the resolved items are
// written to the pantry. Mirrors VoiceMealLogView's phase machine.
//
// Two save paths, chosen per-item via a SET/ADD toggle:
//   - SET (current total): viewModel.setPantryItem(...) → setOrCreate (REPLACE).
//     The card shows old → new because this is a destructive overwrite.
//   - ADD (a purchase): viewModel.addPantryItem(...) → mergeOrCreate (additive).
//

import SwiftUI

struct VoicePantryView: View {
    /// Pantry ViewModel — used both to save (add/set) and to read current
    /// stock for the SET old→new preview. Passed in like PantryView, NOT
    /// pulled from the environment (this codebase wires the VM explicitly).
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dismiss)
    private var dismiss

    @State private var transcriber = VoiceTranscriber()
    @State private var service: VoicePantryService?

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
    @State private var resolved: [VoiceResolvedPantryItem] = []
    /// Parallel mutable per-item intent (the immutable resolved items can't be
    /// edited in place). `true` == SET, `false` == ADD. Seeded when entering
    /// `.confirming`: defaults to the AI's intent, but a low-confidence item is
    /// FORCED to ADD because SET is destructive.
    @State private var effectiveSet: [Bool] = []

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
            .navigationTitle("Add to Pantry by Voice")
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
                service = VoicePantryService(apiClient: services.apiClient)
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
                ? "Listening… say what's in your pantry"
                : "Tap the mic and say what's in your pantry")
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
            Text("Reading your pantry…")
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
            // Seed the per-item SET/ADD state. Default to the AI's intent, but
            // force ADD for low-confidence items — a destructive SET must never
            // be the silent default on an uncertain parse.
            effectiveSet = resolved.map { $0.isSet && !$0.isLowConfidence }
            phase = resolved.isEmpty
                ? .failed("No pantry items found.")
                : .confirming
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("Confirm your pantry")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)

            ScrollView {
                VStack(spacing: TempoSpacing.sm) {
                    ForEach(Array(resolved.enumerated()), id: \.offset) { index, item in
                        resolvedRow(item, index: index)
                    }
                }
            }

            Button {
                saveResolvedItems()
            } label: {
                Text("Save to Pantry")
            }
            .buttonStyle(.tempoPrimary)
        }
    }

    @ViewBuilder
    private func resolvedRow(_ item: VoiceResolvedPantryItem, index: Int) -> some View {
        let isSet = index < effectiveSet.count ? effectiveSet[index] : false
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

            // Component breakdown the AI used to reach the aggregated total.
            if !item.components.isEmpty {
                Text(item.components.joined(separator: " + "))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            // Quantity line: SET shows old → new (destructive overwrite),
            // ADD shows the additive delta.
            quantityLine(item, isSet: isSet)

            // Per-item SET/ADD toggle. SET is disabled for low-confidence items
            // so an uncertain parse can never become a silent overwrite.
            Picker("Action", selection: setBinding(for: index)) {
                Text("Add").tag(false)
                if !item.isLowConfidence {
                    Text("Set total").tag(true)
                }
            }
            .pickerStyle(.segmented)
            .disabled(item.isLowConfidence)

            if item.isLowConfidence {
                Button {
                    transcriber.stop()
                    dismiss()
                } label: {
                    Text("Edit manually")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoSignal)
                }
                .buttonStyle(.plain)
            }

            if item.unit == nil {
                Text("No usable unit — won't be saved.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoError)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    @ViewBuilder
    private func quantityLine(_ item: VoiceResolvedPantryItem, isSet: Bool) -> some View {
        let unitLabel = item.unit?.displayName ?? item.unitRaw
        if isSet {
            // Destructive overwrite — show the existing matching row's quantity
            // so a mis-parse is caught before the old value is replaced.
            let current = currentQuantity(for: item)
            let oldText = current.map { "\(formatQuantity($0)) \(unitLabel)" } ?? "—"
            Text("\(oldText) → \(formatQuantity(item.quantity)) \(unitLabel)")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        } else {
            Text("+\(formatQuantity(item.quantity)) \(unitLabel)")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    /// Current quantity of the existing pantry row that `setOrCreate` would
    /// overwrite. Matches the service's rule EXACTLY (canonical name AND unit)
    /// so the preview can't disagree with the save.
    private func currentQuantity(for item: VoiceResolvedPantryItem) -> Double? {
        guard let unit = item.unit else { return nil }
        let canonical = FoodCanonicalizer.canonicalize(item.name)
        return viewModel.pantryState.items.first {
            $0.canonicalName == canonical && $0.unit == unit
        }?.quantity
    }

    private func setBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { index < effectiveSet.count ? effectiveSet[index] : false },
            set: { newValue in
                guard index < effectiveSet.count else { return }
                // Belt-and-suspenders: never let a low-confidence row flip to SET.
                if resolved[index].isLowConfidence {
                    effectiveSet[index] = false
                } else {
                    effectiveSet[index] = newValue
                }
            }
        )
    }

    private func saveResolvedItems() {
        for (index, item) in resolved.enumerated() {
            // Skip items the AI couldn't assign a usable unit to — don't
            // fabricate grams for something it left blank/unknown.
            guard let unit = item.unit else { continue }
            let isSet = index < effectiveSet.count ? effectiveSet[index] : false
            if isSet {
                viewModel.setPantryItem(
                    rawName: item.name,
                    quantity: item.quantity,
                    unit: unit,
                    storageLocation: item.storage
                )
            } else {
                viewModel.addPantryItem(
                    rawName: item.name,
                    quantity: item.quantity,
                    unit: unit,
                    storageLocation: item.storage,
                    totalPaidUSD: nil
                )
            }
        }
        viewModel.reloadPantry()
        transcriber.stop()
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

    private func formatQuantity(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
