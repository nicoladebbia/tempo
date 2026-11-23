//
// TrainerFeedbackInputView.swift
// Tempo
//
// trainer-feedback-tests — "Trainer sent changes": the athlete pastes the
// trainer's WhatsApp reply as text, or adds a screenshot of it. A screenshot
// is read on-device via Vision OCR (`ProgramTextExtractor.extractText`) —
// deliberately NOT the paid vision proxy `TrainerProgramPageTranscriber`
// uses for real program imports: a WhatsApp bubble is rendered text, not a
// photographed sheet, on-device OCR reads it just fine, and it means this
// whole feature costs nothing extra (no quota, no vision call) for something
// this small. STRUCTURE (`TrainerFeedbackService`/`TrainerFeedbackParser`)
// turns the combined text into raw edits; `TrainerFeedbackReviewView` takes
// it from there for match + toggle + apply.
//

import PhotosUI
import SwiftUI
import UIKit

// MARK: - TrainerFeedbackInputView

struct TrainerFeedbackInputView: View {
    let program: TrainerProgram

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var feedbackService: TrainerFeedbackService?
    @State
    private var text = ""
    @State
    private var screenshot: UIImage?
    @State
    private var photosSelection: PhotosPickerItem?
    @State
    private var isProcessing = false
    @State
    private var processingLabel = "Reading the screenshot…"
    @State
    private var errorMessage: String?
    @State
    private var reviewPayload: ReviewPayload?
    @FocusState
    private var textFocused: Bool

    struct ReviewPayload: Identifiable {
        let id = UUID()
        let sourceText: String
        let edits: [ResolvedTrainerFeedbackEdit]
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || screenshot != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isProcessing {
                    processingOverlay
                } else {
                    formContent
                }
            }
            .navigationTitle("Trainer Sent Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .trainSheetRoot(energy: 0.8)
        .onAppear {
            if feedbackService == nil {
                feedbackService = TrainerFeedbackService(apiClient: services.apiClient)
            }
        }
        .onChange(of: photosSelection) { _, newItem in
            guard let newItem else {
                return
            }
            Task { await loadScreenshot(newItem) }
        }
        .sheet(item: $reviewPayload) { payload in
            TrainerFeedbackReviewView(
                program: program,
                sourceText: payload.sourceText,
                edits: payload.edits,
                onApplied: { dismiss() }
            )
        }
    }

    // MARK: - Form

    private var formContent: some View {
        TrainPlanPage(spacing: Tide.s4) {
            VStack(alignment: .leading, spacing: Tide.s2) {
                Text("Paste what your trainer sent")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "\"RDL +5kg\", \"skip the sprints Thursday, knee\", \"togli gli sprint giovedì\" — Tempo turns it into changes you review before anything's applied."
                )
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Tide.s2)

            TextEditor(text: $text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .scrollContentBackground(.hidden)
                .focused($textFocused)
                .padding(.vertical, Tide.s2)
                .frame(minHeight: TideTrain.textArea)
                .tideFieldSurface(focused: textFocused)

            PhotosPicker(selection: $photosSelection, matching: .images) {
                Label("Add a Screenshot Instead", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)

            if let screenshot {
                HStack(spacing: Tide.s3) {
                    Image(uiImage: screenshot)
                        .resizable()
                        .scaledToFill()
                        .frame(width: TideTrain.rowThumb, height: TideTrain.rowThumb)
                        .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius))
                        .accessibilityHidden(true)
                    Text("Screenshot added — its text will be read on-device.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    Button {
                        self.screenshot = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Tide.title2)
                            .foregroundStyle(Tide.text3)
                            .frame(width: Tide.hit, height: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove screenshot")
                }
                .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }

            Button {
                Task { await submit() }
            } label: {
                Text("Read Changes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tidePrimary)
            .disabled(!canSubmit)

            #if DEBUG
                Button("Load Sample Changes (DEBUG)") {
                    loadSampleReview()
                }
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .frame(minHeight: Tide.hit)
            #endif
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var processingOverlay: some View {
        VStack(spacing: Tide.s4) {
            ProgressView().controlSize(.large)
            Text(processingLabel)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tide.s6)
        .tideCard(padding: Tide.s5, radius: Tide.cardRadius)
        .padding(.horizontal, Tide.edge)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Screenshot OCR

    private func loadScreenshot(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            errorMessage = "Couldn't load that screenshot."
            return
        }
        screenshot = image
        photosSelection = nil
    }

    // MARK: - Submit

    private func submit() async {
        guard let feedbackService else {
            errorMessage = "Not ready yet — try again."
            return
        }
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        var combinedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let screenshot {
            processingLabel = "Reading the screenshot…"
            if let ocrText = try? await ProgramTextExtractor.extractText(from: screenshot), !ocrText.isEmpty {
                combinedText = combinedText.isEmpty ? ocrText : "\(combinedText)\n\n\(ocrText)"
            } else if combinedText.isEmpty {
                errorMessage = "Couldn't read any text from that screenshot. Try pasting it instead."
                return
            }
        }
        guard !combinedText.isEmpty else {
            errorMessage = "Nothing to read yet."
            return
        }

        processingLabel = "Reading the changes…"
        do {
            let rawEdits = try await feedbackService.structureFeedback(from: combinedText)
            let weekIndex = program.weekIndex(on: Date()) ?? 0
            let resolved = TrainerFeedbackApplier.resolve(
                edits: rawEdits,
                weeks: program.weeks,
                weekIndex: weekIndex,
                scheduleMode: program.scheduleMode
            )
            reviewPayload = ReviewPayload(sourceText: combinedText, edits: resolved)
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return "Something went wrong reading those changes."
    }

    #if DEBUG
        /// DEBUG-only path so the diff review screen can be exercised in the
        /// simulator without a signed-in AI call — mirrors
        /// `TrainerProgramImportView.loadSample()`'s existing convention.
        /// Resolves a fixed set of raw edits against whichever program was
        /// handed to this screen, exactly like a real AI reply would.
        private func loadSampleReview() {
            let sampleText = "RDL +5kg\nskip the sprints Thursday, knee\ntogli il leg press"
            let weekIndex = program.weekIndex(on: Date()) ?? 0
            let rawEdits: [RawTrainerFeedbackEdit] = [
                RawTrainerFeedbackEdit(
                    type: .updateExercise, weekday: nil, exerciseName: "RDL", sets: nil, repsLow: nil,
                    repsHigh: nil, weightKg: nil, weightDeltaKg: 5, restSeconds: nil, notes: nil,
                    moveToWeekday: nil, reason: nil
                ),
                RawTrainerFeedbackEdit(
                    type: .skipSession, weekday: 4, exerciseName: "sprints", sets: nil, repsLow: nil,
                    repsHigh: nil, weightKg: nil, weightDeltaKg: nil, restSeconds: nil, notes: nil,
                    moveToWeekday: nil, reason: "knee"
                ),
                RawTrainerFeedbackEdit(
                    type: .removeExercise, weekday: nil, exerciseName: "Leg Press", sets: nil, repsLow: nil,
                    repsHigh: nil, weightKg: nil, weightDeltaKg: nil, restSeconds: nil, notes: nil,
                    moveToWeekday: nil, reason: nil
                ),
            ]
            let resolved = TrainerFeedbackApplier.resolve(
                edits: rawEdits,
                weeks: program.weeks,
                weekIndex: weekIndex,
                scheduleMode: program.scheduleMode
            )
            reviewPayload = ReviewPayload(sourceText: sampleText, edits: resolved)
        }
    #endif
}
