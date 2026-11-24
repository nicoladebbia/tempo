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
            Group {
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
            .animation(Tide.snap, value: phase)
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

    /// The words and the example phrases (or, once talking, what has been
    /// heard so far) fill the page; the mic sits at the bottom, under the thumb.
    private var micSection: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Tide.s5) {
                    KitchenStateText(
                        title: transcriber.isListening ? "Listening…" : "List what's in your pantry",
                        message: transcriber.isListening
                            ? "Name everything, then tap stop."
                            : "Tap the mic and go one after another, the way you'd say it out loud."
                    )
                    .padding(.top, Tide.s6)
                    if transcriber.isListening || !transcriber.transcribedText.isEmpty {
                        heardCard
                    } else {
                        examplesCard
                    }
                    if let err = transcriber.error {
                        KitchenNotice(systemImage: "exclamationmark.triangle.fill", text: err, tint: Tide.danger)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .frame(maxWidth: Tide.stateWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            micControl
        }
        .animation(Tide.snap, value: transcriber.transcribedText.isEmpty)
    }

    /// What has been heard so far, growing as the person talks.
    private var heardCard: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("You said").tideLabel(Tide.text3)
            if transcriber.transcribedText.isEmpty {
                Text("Go ahead, I'm listening…")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text3)
            } else {
                Text(transcriber.transcribedText)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Three lines to copy the shape of, so the first try works.
    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Try saying").tideLabel(Tide.text3)
            example("Two cartons of eggs in the fridge")
            example("A kilo of basmati rice")
            example("Olive oil and a jar of peanut butter")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .transition(.opacity)
    }

    private func example(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
            Image(systemName: "quote.opening")
                .font(Tide.caption)
                .foregroundStyle(mood.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var micControl: some View {
        VStack(spacing: Tide.s3) {
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
            .sensoryFeedback(.impact, trigger: transcriber.isListening)
            .accessibilityLabel(transcriber.isListening ? "Stop listening" : "Start listening")
            Text(transcriber.isListening ? "Tap to stop" : "Tap to start")
                .tideLabel(Tide.text3)
        }
        .padding(.top, Tide.s5)
        .padding(.bottom, Tide.s4)
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
        ScrollView {
            VStack(spacing: Tide.s5) {
                KitchenStateHero(
                    systemImage: "list.bullet.clipboard",
                    title: "Reading your pantry…",
                    message: "Turning what you said into items.",
                    working: true
                )
                .padding(.top, Tide.s6)
                if !transcriber.transcribedText.isEmpty {
                    Text(transcriber.transcribedText)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
                // The shape of what is coming: a confirm card per item.
                VStack(spacing: Tide.s3) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                            .fill(Tide.fill)
                            .frame(height: Tide.Kitchen.row + Tide.s6)
                    }
                }
                .shimmer()
            }
            .padding(.horizontal, Tide.edge)
            .frame(maxWidth: Tide.stateWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading your pantry")
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
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Confirm your pantry", trailing: "\(editable.count) found")
                Text("Edit anything, remove what's wrong, then save.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                // Bind by id so a per-row remove can't desync indices.
                ForEach($editable) { $row in
                    editableRow($row)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
        }
        .scrollIndicators(.hidden)
        .kitchenBottomBar {
            Button {
                saveEditableItems()
            } label: {
                Text(editable.isEmpty ? "Nothing to save" : "Save \(editable.count) to Pantry")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kitchenBar)
            .disabled(editable.isEmpty)
        }
    }

    @ViewBuilder
    private func editableRow(_ row: Binding<EditableItem>) -> some View {
        let item = row.wrappedValue
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .top, spacing: Tide.s2) {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(item.name)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.isLowConfidence {
                        KitchenTag(text: "Low confidence", tint: Tide.Kitchen.warn)
                    }
                }
                Spacer(minLength: Tide.s2)
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
            VStack(alignment: .leading, spacing: Tide.s1) {
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
            }

            // Quantity, unit and shelf on one line; stacked when the text is large.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) {
                    quantityField(row)
                    unitPicker(row)
                    Spacer(minLength: Tide.s2)
                    storagePicker(row, item: item)
                }
                VStack(alignment: .leading, spacing: Tide.s2) {
                    HStack(spacing: Tide.s2) {
                        quantityField(row)
                        unitPicker(row)
                    }
                    storagePicker(row, item: item)
                }
            }

            // SET shows old → new (destructive overwrite); ADD shows the delta.
            // Reactive to the edited quantity + unit.
            changeChip(item)

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

    private func quantityField(_ row: Binding<EditableItem>) -> some View {
        TextField("Qty", text: row.quantityText)
            .keyboardType(.decimalPad)
            .font(Tide.body)
            .frame(maxWidth: Tide.Kitchen.row + Tide.s5, minHeight: Tide.hit - Tide.s4)
            .padding(Tide.s2)
            .background(Tide.fill)
            .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous).stroke(Tide.hairline, lineWidth: 1))
    }

    private func unitPicker(_ row: Binding<EditableItem>) -> some View {
        Picker("Unit", selection: row.unit) {
            ForEach(PantryUnit.allCases, id: \.self) { u in
                Text(u.displayName).tag(u)
            }
        }
        .pickerStyle(.menu)
        .tint(mood.accent)
    }

    /// The AI assigns the shelf from the spoken section ("in the fridge…"); the
    /// user can correct it here, with its icon beside it.
    private func storagePicker(_ row: Binding<EditableItem>, item: EditableItem) -> some View {
        HStack(spacing: Tide.s1) {
            Image(systemName: storageIcon(item.storage))
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .accessibilityHidden(true)
            Picker("Location", selection: row.storage) {
                ForEach(PantryStorageLocation.allCases, id: \.self) { loc in
                    Text(loc.displayName).tag(loc)
                }
            }
            .pickerStyle(.menu)
            .tint(mood.accent)
        }
        .fixedSize()
    }

    /// What saving does to the pantry, in a pill: a set replaces the total
    /// (amber, because it overwrites), an add tops it up.
    private func changeChip(_ item: EditableItem) -> some View {
        let text: String
        let tint: Color
        let icon: String
        if item.isSet {
            let oldText = currentQuantity(name: item.name, unit: item.unit)
                .map { "\(formatQuantity($0)) \(item.unit.displayName)" } ?? "—"
            text = "\(oldText) → \(formatQuantity(item.quantity)) \(item.unit.displayName)"
            tint = Tide.Kitchen.warn
            icon = "arrow.triangle.2.circlepath"
        } else {
            text = "+\(formatQuantity(item.quantity)) \(item.unit.displayName)"
            tint = Tide.text2
            icon = "plus"
        }
        return HStack(spacing: Tide.s1) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(Tide.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, Tide.s3)
        .padding(.vertical, Tide.s1)
        .background(Tide.fill, in: .capsule)
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
        KitchenStatePage {
            AIBlockerCard(blocker: blocker, onConsentGranted: retry)
        }
    }

    private func failureSection(_ message: String) -> some View {
        // transcriber.start() clears transcribedText itself.
        KitchenStatePage(actions: [
            KitchenStateAction(title: "Try again", systemImage: "mic.fill", role: .primary) {
                phase = .idle
            },
        ]) {
            KitchenStateHero(
                systemImage: "exclamationmark.triangle.fill",
                tint: Tide.danger,
                title: "That didn't work",
                message: message
            )
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
