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
                Color.tempoBgPrimary.ignoresSafeArea()
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
        .preferredColorScheme(.dark)
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("Paste what your trainer sent")
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(
                        "\"RDL +5kg\", \"skip the sprints Thursday, knee\", \"togli gli sprint giovedì\" — Tempo turns it into changes you review before anything's applied."
                    )
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                }

                TextEditor(text: $text)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(TempoSpacing.sm)
                    .frame(minHeight: 140)
                    .background(Color.tempoInputBgDark.opacity(TempoOpacity.o40))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.xl)
                            .stroke(Color.tempoBorder, lineWidth: 1)
                    )

                PhotosPicker(selection: $photosSelection, matching: .images) {
                    Label("Add a Screenshot Instead", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)

                if let screenshot {
                    HStack(spacing: TempoSpacing.sm) {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm))
                        Text("Screenshot added — its text will be read on-device.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        Spacer()
                        Button {
                            self.screenshot = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text("Read Changes")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                .disabled(!canSubmit)

                #if DEBUG
                    Button("Load Sample Changes (DEBUG)") {
                        loadSampleReview()
                    }
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.top, TempoSpacing.md)
                #endif
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
    }

    private var processingOverlay: some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView().scaleEffect(1.4)
            Text(processingLabel)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
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
            let resolved = TrainerFeedbackApplier.resolve(edits: rawEdits, weeks: program.weeks, weekIndex: weekIndex)
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
            let resolved = TrainerFeedbackApplier.resolve(edits: rawEdits, weeks: program.weeks, weekIndex: weekIndex)
            reviewPayload = ReviewPayload(sourceText: sampleText, edits: resolved)
        }
    #endif
}
