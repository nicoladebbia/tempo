//
// TrainerProgramImportView.swift
// Tempo
//
// Multi-source intake for a Trainer Program import: the athlete adds several
// sources to ONE import (e.g. "LIFT SESSIONS.pdf" + "CONDITIONING
// SESSIONS.pdf"), sees them listed with remove buttons, then taps "Read
// Program" to run the pipeline:
//   NORMALIZE (TrainerProgramSourceNormalizer) — every source becomes page
//     images (+ on-device text hints) or, for already-digital text, plain
//     text that skips straight to structuring.
//   TRANSCRIBE (TrainerProgramPageTranscriber) — every page image goes
//     through the Sonnet vision proxy for a faithful row-by-row
//     transcription; on-device OCR alone drops small table cells on real
//     trainer sheets, which is why this step exists at all.
//   STRUCTURE (TrainerProgramImportService / TrainerProgramParser) — the
//     combined transcript is parsed into a program via the Sonnet text
//     proxy, same as before.
// TrainerProgramReviewView takes it from there for edit-before-save.
//

import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - TrainerProgramImportView

struct TrainerProgramImportView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var importService: TrainerProgramImportService?

    @State
    private var sources: [ProgramImportSource] = []

    @State
    private var isProcessing = false
    @State
    private var importTask: Task<Void, Never>?
    @State
    private var processingLabel = "Reading your program…"
    @State
    private var errorMessage: String?

    @State
    private var showCameraPicker = false
    @State
    private var photosSelection: [PhotosPickerItem] = []
    @State
    private var showFileImporter = false
    @State
    private var showPasteSheet = false

    @State
    private var reviewPayload: ReviewPayload?

    /// Bundles what TrainerProgramReviewView needs — a single Identifiable
    /// item keeps the sheet presentation simple.
    struct ReviewPayload: Identifiable {
        let id = UUID()
        let parsed: TrainerProgramParser.ParsedProgram
        let sourceKind: String
        let sourceText: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary.ignoresSafeArea()
                if isProcessing {
                    processingOverlay
                } else {
                    sourcePicker
                }
            }
            .navigationTitle("Import from Trainer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Stop any in-flight reading (page transcriptions and the
                        // structure call are network requests — don't let them
                        // run on, and bill, after the sheet is gone).
                        importTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        // Matches the convention every standalone onboarding screen already
        // follows for a modally-presented dark-only screen.
        .preferredColorScheme(.dark)
        .onAppear {
            if importService == nil {
                importService = TrainerProgramImportService(apiClient: services.apiClient)
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            TrainerProgramImagePicker(sourceType: .camera) { image in
                showCameraPicker = false
                if let image {
                    addSource(.init(displayName: "Photo \(sources.count + 1)", payload: .image(image)))
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: TrainerProgramSourceNormalizer.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                for url in urls {
                    addSource(.init(displayName: url.lastPathComponent, payload: .fileURL(url)))
                }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: photosSelection) { _, newItems in
            guard !newItems.isEmpty else {
                return
            }
            Task { await loadPhotos(newItems) }
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteTextSheet { text in
                addSource(.init(displayName: "Pasted text \(sources.count + 1)", payload: .pastedText(text)))
            }
        }
        .sheet(item: $reviewPayload) { payload in
            TrainerProgramReviewView(
                parsed: payload.parsed,
                sourceKind: payload.sourceKind,
                sourceText: payload.sourceText,
                onSaved: { dismiss() }
            )
        }
    }

    // MARK: - Source picker

    private var sourcePicker: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xxl) {
                VStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.tempoViolet)
                    Text("Get your coach's program into Tempo")
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .multilineTextAlignment(.center)
                    Text(
                        "Add every sheet your coach sent — photos, PDFs, Word/Excel files, or pasted text. Tempo reads them all as one program and you review before it goes live."
                    )
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)
                }
                .padding(.top, TempoSpacing.xl)
                .padding(.horizontal, TempoSpacing.xl)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TempoSpacing.xl)
                }

                if !sources.isEmpty {
                    sourceListSection
                }

                addSourceButtons

                if !sources.isEmpty {
                    Button {
                        importTask?.cancel()
                        importTask = Task { await readProgram() }
                    } label: {
                        Text("Read Program")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tempoPrimary)
                    .padding(.horizontal, TempoSpacing.screenEdge)
                }

                #if DEBUG
                    Button("Load Sample Program (DEBUG)") {
                        loadSample()
                    }
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.top, TempoSpacing.md)
                #endif
            }
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
    }

    // MARK: - Added sources list

    private var sourceListSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("SOURCES")
                .font(.tempoCaption2.weight(.bold))
                .foregroundStyle(Color.tempoTextTertiary)

            ForEach(sources) { source in
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: source.systemImage)
                        .foregroundStyle(Color.tempoViolet)
                        .frame(width: 24)
                    Text(source.displayName)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        removeSource(source.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .accessibilityLabel("Remove \(source.displayName)")
                }
                .padding(TempoSpacing.cardPaddingCompact)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg))
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private var addSourceButtons: some View {
        VStack(spacing: TempoSpacing.md) {
            Button {
                showCameraPicker = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)

            PhotosPicker(
                selection: $photosSelection,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Choose Photos", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)

            Button {
                showFileImporter = true
            } label: {
                Label("Choose Files", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)

            Button {
                showPasteSheet = true
            } label: {
                Label("Paste Text", systemImage: "text.alignleft")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private var processingOverlay: some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView().scaleEffect(1.4)
            Text(processingLabel)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Source list mutation

    private func addSource(_ source: ProgramImportSource) {
        sources.append(source)
        errorMessage = nil
    }

    private func removeSource(_ id: UUID) {
        sources.removeAll { $0.id == id }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        errorMessage = nil
        var loaded: [ProgramImportSource] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(.init(displayName: "Photo \(sources.count + loaded.count + 1)", payload: .image(image)))
            }
        }
        photosSelection = []
        guard !loaded.isEmpty else {
            errorMessage = "Couldn't load those photos."
            return
        }
        sources.append(contentsOf: loaded)
    }

    // MARK: - Pipeline

    /// NORMALIZE -> TRANSCRIBE -> STRUCTURE, driven from the current
    /// `sources` list. Progress narrates the transcription step ("Reading
    /// page 2 of 5…") since that's the slow, per-page part.
    private func readProgram() async {
        guard let importService else {
            errorMessage = "Not ready yet — try again."
            return
        }
        errorMessage = nil
        isProcessing = true
        processingLabel = "Reading your sources…"
        defer { isProcessing = false }
        do {
            let units = try await TrainerProgramSourceNormalizer.normalize(sources)
            try Task.checkCancellation()
            let transcript = try await TrainerProgramPageTranscriber.transcribe(
                units: units,
                apiClient: services.apiClient,
                onProgress: { completed, total in
                    Task { @MainActor in
                        processingLabel = "Reading page \(completed) of \(total)…"
                    }
                }
            )
            try Task.checkCancellation()
            processingLabel = "Structuring your program…"
            let parsed = try await importService.structureProgram(from: transcript)
            try Task.checkCancellation()
            reviewPayload = ReviewPayload(parsed: parsed, sourceKind: sourceKindLabel, sourceText: transcript)
        } catch is CancellationError {
            // Cancelled by the user — nothing to report.
        } catch {
            errorMessage = message(for: error)
        }
    }

    private var sourceKindLabel: String {
        guard sources.count == 1, let only = sources.first else {
            return "multi"
        }
        switch only.payload {
        case .image:
            return "photo"
        case .pastedText:
            return "text"
        case let .fileURL(url):
            switch TrainerProgramSourceNormalizer.routingKind(for: url) {
            case .pdf,
                 .officeConvertible:
                return "pdf"
            case .image:
                return "photo"
            case .text:
                return "text"
            }
        }
    }

    private func message(for error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return "Something went wrong reading that program."
    }

    #if DEBUG
        /// DEBUG-only path so the review screen (and the rest of the save flow)
        /// can be exercised in the simulator without a signed-in AI call.
        /// Mirrors a realistic two-file program: 2 lift sessions with A/A
        /// supersets, 3 conditioning sessions, all with weekday null (Tempo
        /// places them) — the same shape as a real coach's PDF pair.
        private func loadSample() {
            reviewPayload = ReviewPayload(
                parsed: Self.sampleParsedProgram,
                sourceKind: "multi",
                sourceText: "DEBUG sample — no real source text."
            )
        }

        static let sampleParsedProgram = TrainerProgramParser.ParsedProgram(
            name: "Coach — Lift + Conditioning",
            weeks: [
                ProgramWeek(days: [
                    ProgramDay(
                        weekday: 1,
                        title: "Hypertrophy Lifting 1",
                        focus: WorkoutType.fullBody.rawValue,
                        exercises: [
                            ProgramExercise(
                                name: "Leg Press", exerciseID: nil, sets: 3, repsLow: 8, repsHigh: nil,
                                weightKg: nil, rpe: nil, percentOf1RM: 0.7, restSeconds: nil, group: 1, notes: nil
                            ),
                            ProgramExercise(
                                name: "SA Incline DB Chest Press", exerciseID: nil, sets: 3, repsLow: 8, repsHigh: nil,
                                weightKg: nil, rpe: nil, percentOf1RM: 0.7, restSeconds: 60, group: 1, notes: nil
                            ),
                            ProgramExercise(
                                name: "KT Lat Step Up", exerciseID: nil, sets: 3, repsLow: 8, repsHigh: nil,
                                weightKg: nil, rpe: nil, percentOf1RM: 0.7, restSeconds: nil, group: 2, notes: nil,
                                detail: nil, perSide: true
                            ),
                        ],
                        notes: nil,
                        weekdayGuessed: true
                    ),
                    ProgramDay(
                        weekday: 3,
                        title: "Hypertrophy Lifting 2",
                        focus: WorkoutType.fullBody.rawValue,
                        exercises: [
                            ProgramExercise(
                                name: "Leg Extension", exerciseID: nil, sets: 3, repsLow: 8, repsHigh: nil,
                                weightKg: nil, rpe: nil, percentOf1RM: 0.7, restSeconds: nil, group: 1, notes: nil
                            ),
                            ProgramExercise(
                                name: "SA DB Row", exerciseID: nil, sets: 3, repsLow: 8, repsHigh: nil,
                                weightKg: nil, rpe: nil, percentOf1RM: 0.7, restSeconds: 60, group: 1,
                                notes: "On SL RDL position"
                            ),
                        ],
                        notes: nil,
                        weekdayGuessed: true
                    ),
                    ProgramDay(
                        weekday: 2,
                        title: "Aerobic Run",
                        focus: WorkoutType.run.rawValue,
                        exercises: [
                            ProgramExercise(
                                name: "Warm Up", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                                weightKg: nil, rpe: 6, percentOf1RM: nil, restSeconds: nil, group: nil,
                                notes: "Without ball", detail: "5'", perSide: nil
                            ),
                            ProgramExercise(
                                name: "Fartleck", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                                weightKg: nil, rpe: 8, percentOf1RM: nil, restSeconds: nil, group: nil,
                                notes: "With the ball", detail: "35' — 2' slow / 1' fast / 30\" walk + juggling", perSide: nil
                            ),
                            ProgramExercise(
                                name: "Cool Down", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                                weightKg: nil, rpe: 6, percentOf1RM: nil, restSeconds: nil, group: nil,
                                notes: "Without ball", detail: "10'", perSide: nil
                            ),
                        ],
                        notes: nil,
                        weekdayGuessed: true
                    ),
                    ProgramDay(
                        weekday: 4,
                        title: "Anaerobic Run",
                        focus: WorkoutType.sprint.rawValue,
                        exercises: [
                            ProgramExercise(
                                name: "Shuttle 1", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                                weightKg: nil, rpe: 9, percentOf1RM: nil, restSeconds: 90, group: nil,
                                notes: "300y total", detail: "4 reps of 25y out and back in < 65\"", perSide: nil
                            ),
                            ProgramExercise(
                                name: "Shuttle 2", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                                weightKg: nil, rpe: 9, percentOf1RM: nil, restSeconds: 90, group: nil,
                                notes: "320y total", detail: "4 reps 80y out and back in < 55\"", perSide: nil
                            ),
                        ],
                        notes: "Follow the order: S1 - Rest - S2 - Rest - S2 - Rest - S1",
                        weekdayGuessed: true
                    ),
                    ProgramDay(
                        weekday: 6,
                        title: "Speed Development Conditioning",
                        focus: WorkoutType.conditioning.rawValue,
                        exercises: [
                            ProgramExercise(
                                name: "Run", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                                weightKg: nil, rpe: 7, percentOf1RM: nil, restSeconds: nil, group: nil,
                                notes: nil, detail: "15' easy", perSide: nil
                            ),
                            ProgramExercise(
                                name: "T Drill", exerciseID: nil, sets: 2, repsLow: 10, repsHigh: nil,
                                weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: 1,
                                notes: "When you feel ready, but 2' in between", detail: "10m + 5m", perSide: nil
                            ),
                            ProgramExercise(
                                name: "Arrow Drill", exerciseID: nil, sets: 2, repsLow: 10, repsHigh: nil,
                                weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: nil, group: 1,
                                notes: "When you feel ready, but 2' in between", detail: "10m + 5m", perSide: nil
                            ),
                            ProgramExercise(
                                name: "Run", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                                weightKg: nil, rpe: 6, percentOf1RM: nil, restSeconds: nil, group: nil,
                                notes: nil, detail: "10' easy", perSide: nil
                            ),
                        ],
                        notes: nil,
                        weekdayGuessed: true
                    ),
                ]),
            ],
            autoAssignedWeekdays: true
        )
    #endif
}

// MARK: - TrainerProgramImagePicker

private struct TrainerProgramImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func imagePickerController(_: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onPick(image)
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            onPick(nil)
        }
    }
}

// MARK: - PasteTextSheet

/// Small standalone sheet for the "Paste Text" source — kept separate from
/// the main picker so adding pasted text doesn't require a dedicated
/// always-visible text box competing with the other three source buttons.
private struct PasteTextSheet: View {
    var onAdd: (String) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.md) {
                TextEditor(text: $text)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(TempoSpacing.sm)
                    .background(Color.tempoInputBgDark.opacity(TempoOpacity.o40))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.xl)
                            .stroke(Color.tempoBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.top, TempoSpacing.lg)

                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        return
                    }
                    onAdd(trimmed)
                    dismiss()
                } label: {
                    Text("Add")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, TempoSpacing.screenEdge)

                Spacer()
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Paste Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
