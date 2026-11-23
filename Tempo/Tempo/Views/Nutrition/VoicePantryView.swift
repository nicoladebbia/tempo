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
    @Environment(\.tideMood)
    private var mood

    @State private var transcriber = VoiceTranscriber()
    @State private var service: VoicePantryService?

    private enum Phase: Equatable {
        case idle
        case recording
        case thinking
        case confirming
        case failed(String)
        /// Pro / AI-off: the card offers the fix.
        case blocked(AIBlocker)
    }

    /// A mutable, per-row editable copy of one resolved item. The confirm card
    /// is now the SOLE correction surface (the clarifying-questions phase was
    /// removed — it crashed on a model-generated "Other" option and forced a
    /// blocking modal per item, wrong for a bulk stock-take). Everything the
    /// user can fix lives here: quantity, unit, SET/ADD intent, and removal.
    struct EditableItem: Identifiable {
        let id = UUID()
        var name: String
        var brand: String
        var quantityText: String
        var unit: PantryUnit
        var storage: PantryStorageLocation
        var isSet: Bool
        var components: [String]
        var isLowConfidence: Bool

        var quantity: Double { Double(quantityText) ?? 0 }
    }

    @State private var phase: Phase = .idle
    @State private var editable: [EditableItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: Tide.s5) {
                switch phase {
                case .idle, .recording:
                    micSection
                case .thinking:
                    thinkingSection
                case .confirming:
                    confirmationSection
                case let .failed(message):
                    failureSection(message)
                case let .blocked(blocker):
                    blockedSection(blocker) { Task { await runResolve() } }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(Tide.edge)
            .kitchenPage()
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
            // No silence auto-stop + continuous mode: a pantry stock-take is a
            // long list ("I have rice… pasta… olive oil…") with natural pauses.
            // continuousMode keeps capturing across Apple's mid-speech segment
            // finalizations; the user ends it by tapping Stop, not by pausing.
            transcriber.silenceTimeout = 0
            transcriber.continuousMode = true
        }
        .onChange(of: transcriber.isListening) { wasListening, nowListening in
            // Manual Stop (the user tapped it) ends recording → resolve straight
            // to the editable confirm card (no clarifying phase, no auto-stop).
            #if DEBUG
                print("[VoicePantry] isListening \(wasListening)→\(nowListening) phase=\(phase) transcript=\"\(transcriber.transcribedText)\"")
            #endif
            if wasListening, !nowListening, phase == .recording {
                Task { await runResolve() }
            }
        }
    }

    // MARK: - Mic

    private var micSection: some View {
        VStack(spacing: Tide.s5) {
            Spacer()

            Text(transcriber.isListening
                ? "Listening… name everything, then tap stop"
                : "Tap the mic and list what's in your pantry, one after another")
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
            #if DEBUG
                print("[VoicePantry] Stop tapped — transcript=\"\(transcriber.transcribedText)\"")
            #endif
            transcriber.stop() // onChange triggers resolve
        } else {
            phase = .recording
            #if DEBUG
                print("[VoicePantry] Start tapped — requesting mic…")
            #endif
            await transcriber.start()
            #if DEBUG
                print("[VoicePantry] start() returned — isListening=\(transcriber.isListening) error=\(transcriber.error ?? "nil")")
            #endif
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
            Text("Reading your pantry…")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            Spacer()
        }
    }

    // MARK: - Resolve → editable confirm card (no clarifying phase)

    private func runResolve() async {
        await runResolveOn(transcriber.transcribedText)
    }

    /// Resolve a transcript (live or, in DEBUG, a seeded one) into editable rows.
    private func runResolveOn(_ rawTranscript: String) async {
        guard let service else { return }
        let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            // Don't vanish silently — tell the user nothing was captured so the
            // screen never just sits there after a Stop.
            phase = .failed("I didn't catch anything. Tap the mic and try again, speaking clearly.")
            return
        }
        phase = .thinking
        do {
            let resolved = try await service.resolve(transcript: transcript, answers: [:])
            // Build the mutable rows. Drop items with no usable unit (the AI
            // left it blank/unknown) rather than fabricating grams. Default to
            // the AI's intent, but FORCE ADD for low-confidence items — a
            // destructive SET must never be the silent default on a guess.
            editable = resolved.compactMap { item in
                guard let unit = item.unit else { return nil }
                return EditableItem(
                    name: item.name,
                    brand: item.brand ?? "",
                    quantityText: formatQuantity(item.quantity),
                    unit: unit,
                    storage: item.storage,
                    isSet: item.isSet && !item.isLowConfidence,
                    components: item.components,
                    isLowConfidence: item.isLowConfidence
                )
            }
            phase = editable.isEmpty
                ? .failed("No pantry items found. Try again.")
                : .confirming
        } catch {
            phase = AIBlocker(error).map(Phase.blocked) ?? .failed(AIBlocker.readableDescription(error))
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Confirm your pantry")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            Text("Edit anything, remove what's wrong, then save.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)

            ScrollView {
                VStack(spacing: Tide.s3) {
                    // Bind by id so a per-row remove can't desync indices.
                    ForEach($editable) { $row in
                        editableRow($row)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button {
                saveEditableItems()
            } label: {
                Text(editable.isEmpty ? "Nothing to save" : "Save \(editable.count) to Pantry")
            }
            .buttonStyle(.tidePrimary)
            .disabled(editable.isEmpty)
        }
    }

    @ViewBuilder
    private func editableRow(_ row: Binding<EditableItem>) -> some View {
        let item = row.wrappedValue
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack {
                Text(item.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Spacer()
                if item.isLowConfidence {
                    KitchenTag(text: "Low confidence", tint: Tide.Kitchen.warn)
                }
                // Per-row remove — drops just this item, never the whole flow.
                Button {
                    editable.removeAll { $0.id == item.id }
                } label: {
                    Image(systemName: "trash")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.danger)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.name)")
            }

            // Brand / description the AI heard ("Land O'Lakes", "50% more
            // protein"). Editable so the user can correct or add one. This is
            // shown but not yet persisted — wiring it into the saved row is the
            // merge-key step (so two brands of the same food stay separate).
            TextField("Brand / description (optional)", text: row.brand)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .textInputAutocapitalization(.words)

            // Component breakdown the AI used to reach the aggregated total.
            if !item.components.isEmpty {
                Text(item.components.joined(separator: " + "))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }

            // Editable quantity + unit.
            HStack(spacing: Tide.s2) {
                TextField("Qty", text: row.quantityText)
                    .keyboardType(.decimalPad)
                    .font(Tide.body)
                    .frame(maxWidth: 90, minHeight: Tide.hit - Tide.s4)
                    .padding(Tide.s2)
                    .background(Tide.fill)
                    .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous).stroke(Tide.hairline, lineWidth: 1))

                Picker("Unit", selection: row.unit) {
                    ForEach(PantryUnit.allCases, id: \.self) { u in
                        Text(u.displayName).tag(u)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }

            // Storage location on its own row so it's unmissable — the AI
            // assigns it from the spoken section ("in the fridge…"); the user
            // can correct it here. Shown as a labeled menu, not just an icon.
            HStack(spacing: Tide.s1) {
                Image(systemName: storageIcon(item.storage))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                Text("Location")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                Picker("Location", selection: row.storage) {
                    ForEach(PantryStorageLocation.allCases, id: \.self) { loc in
                        Text(loc.displayName).tag(loc)
                    }
                }
                .pickerStyle(.menu)
                .tint(mood.accent)
                Spacer()
            }

            // SET shows old → new (destructive overwrite); ADD shows the delta.
            // Reactive to the edited quantity + unit.
            if item.isSet {
                let oldText = currentQuantity(name: item.name, unit: item.unit)
                    .map { "\(formatQuantity($0)) \(item.unit.displayName)" } ?? "—"
                Text("\(oldText) → \(formatQuantity(item.quantity)) \(item.unit.displayName)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            } else {
                Text("+\(formatQuantity(item.quantity)) \(item.unit.displayName)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }

            // Per-item SET/ADD toggle. SET hidden for low-confidence items so an
            // uncertain parse can never become a silent destructive overwrite.
            Picker("Action", selection: intentBinding(row)) {
                Text("Add").tag(false)
                if !item.isLowConfidence {
                    Text("Set total").tag(true)
                }
            }
            .pickerStyle(.segmented)
            .disabled(item.isLowConfidence)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    /// Current quantity of the existing pantry row that `setOrCreate` would
    /// overwrite. Matches the service's rule EXACTLY (canonical name AND unit)
    /// so the preview can't disagree with the save.
    private func currentQuantity(name: String, unit: PantryUnit) -> Double? {
        let canonical = FoodCanonicalizer.canonicalize(name)
        return viewModel.pantryState.items.first {
            $0.canonicalName == canonical && $0.unit == unit
        }?.quantity
    }

    /// SET/ADD binding that can never flip a low-confidence row to SET.
    private func intentBinding(_ row: Binding<EditableItem>) -> Binding<Bool> {
        Binding(
            get: { row.wrappedValue.isSet },
            set: { newValue in
                row.wrappedValue.isSet = row.wrappedValue.isLowConfidence ? false : newValue
            }
        )
    }

    private func saveEditableItems() {
        for item in editable {
            // Skip rows the user zeroed out or left blank.
            guard item.quantity > 0 else { continue }
            let brand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isSet {
                viewModel.setPantryItem(
                    rawName: item.name,
                    quantity: item.quantity,
                    unit: item.unit,
                    storageLocation: item.storage,
                    brand: brand
                )
            } else {
                viewModel.addPantryItem(
                    rawName: item.name,
                    quantity: item.quantity,
                    unit: item.unit,
                    storageLocation: item.storage,
                    totalPaidUSD: nil,
                    brand: brand
                )
            }
        }
        viewModel.reloadPantry()
        transcriber.stop()
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
                .font(Tide.largeTitle)
                .foregroundStyle(Tide.Kitchen.warn)
                .accessibilityHidden(true)
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

    private func formatQuantity(_ value: Double) -> String {
        PantryQuantityFormatter.number(value)
    }

    private func storageIcon(_ loc: PantryStorageLocation) -> String {
        switch loc {
        case .fridge: "thermometer.snowflake"
        case .freezer: "snowflake"
        case .pantry: "archivebox"
        case .cupboard: "archivebox"
        }
    }
}
