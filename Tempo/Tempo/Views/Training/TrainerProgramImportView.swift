//
// TrainerProgramImportView.swift
// Tempo
//
// Source picker for a Trainer Program import: Camera, Photos (several
// images = several pages), PDF, or pasted text. Extraction runs on-device
// (ProgramTextExtractor); structuring calls the Sonnet proxy
// (TrainerProgramImportService) and hands the result to
// TrainerProgramReviewView for edit-before-save.
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
    private var isProcessing = false
    @State
    private var processingLabel = "Reading your program…"
    @State
    private var errorMessage: String?

    @State
    private var showCameraPicker = false
    @State
    private var photosSelection: [PhotosPickerItem] = []
    @State
    private var showPDFImporter = false
    @State
    private var pastedText = ""

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
                    Button("Cancel") { dismiss() }
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
                    Task { await processImages([image]) }
                }
            }
        }
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case let .success(url):
                Task { await processPDF(at: url) }
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
                    Text("Photo of a sheet or whiteboard, a PDF, or paste the text. Tempo reads it and you review before it goes live.")
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
                        showPDFImporter = true
                    } label: {
                        Label("Choose PDF", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tempoSecondary)
                }
                .padding(.horizontal, TempoSpacing.screenEdge)

                pasteSection

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

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("OR PASTE TEXT")
                .font(.tempoCaption2.weight(.bold))
                .foregroundStyle(Color.tempoTextTertiary)

            TextEditor(text: $pastedText)
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

            Button {
                Task { await processPastedText() }
            } label: {
                Text("Structure This Program")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)
            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    // MARK: - Pipeline

    private func processImages(_ images: [UIImage]) async {
        errorMessage = nil
        isProcessing = true
        processingLabel = "Reading your program…"
        defer { isProcessing = false }
        do {
            let text = try await ProgramTextExtractor.extractText(from: images)
            await structure(text: text, sourceKind: "photo")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        errorMessage = nil
        isProcessing = true
        processingLabel = "Loading photos…"
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photosSelection = []
        guard !images.isEmpty else {
            isProcessing = false
            errorMessage = "Couldn't load those photos."
            return
        }
        isProcessing = false
        await processImages(images)
    }

    private func processPDF(at url: URL) async {
        errorMessage = nil
        isProcessing = true
        processingLabel = "Reading your PDF…"
        defer { isProcessing = false }
        do {
            let text = try await ProgramTextExtractor.extractText(fromPDFAt: url)
            await structure(text: text, sourceKind: "pdf")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func processPastedText() async {
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        errorMessage = nil
        isProcessing = true
        processingLabel = "Structuring your program…"
        defer { isProcessing = false }
        await structure(text: trimmed, sourceKind: "text")
    }

    /// Sends already-extracted/pasted text to the Sonnet proxy and, on
    /// success, opens the review sheet. Signed-out users get a plain
    /// explanation — AI structuring genuinely needs a session.
    private func structure(text: String, sourceKind: String) async {
        guard let importService else {
            errorMessage = "Not ready yet — try again."
            return
        }
        isProcessing = true
        processingLabel = "Structuring your program…"
        defer { isProcessing = false }
        do {
            let parsed = try await importService.structureProgram(from: text)
            reviewPayload = ReviewPayload(parsed: parsed, sourceKind: sourceKind, sourceText: text)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong reading that program."
        }
    }

    #if DEBUG
        /// DEBUG-only path so the review screen (and the rest of the save flow)
        /// can be exercised in the simulator without a signed-in AI call.
        private func loadSample() {
            let sample = TrainerProgramParser.ParsedProgram(
                name: "Coach Marco — Push/Pull/Legs",
                weeks: [
                    ProgramWeek(days: [
                        ProgramDay(
                            weekday: 1,
                            title: "Push",
                            focus: WorkoutType.push.rawValue,
                            exercises: [
                                ProgramExercise(
                                    name: "Bench Press", exerciseID: nil, sets: 4, repsLow: 6, repsHigh: 8,
                                    weightKg: 80, rpe: 8, percentOf1RM: nil, restSeconds: 120, group: nil, notes: nil
                                ),
                                ProgramExercise(
                                    name: "Overhead Press", exerciseID: nil, sets: 3, repsLow: 8, repsHigh: 10,
                                    weightKg: nil, rpe: nil, percentOf1RM: 0.7, restSeconds: 90, group: nil, notes: nil
                                ),
                            ],
                            notes: nil
                        ),
                        ProgramDay(
                            weekday: 3,
                            title: "Pull",
                            focus: WorkoutType.pull.rawValue,
                            exercises: [
                                ProgramExercise(
                                    name: "Lat Pulldown", exerciseID: nil, sets: 4, repsLow: 10, repsHigh: 12,
                                    weightKg: nil, rpe: nil, percentOf1RM: nil, restSeconds: 90, group: nil, notes: nil
                                ),
                            ],
                            notes: nil
                        ),
                        ProgramDay(
                            weekday: 5,
                            title: "Legs",
                            focus: WorkoutType.legs.rawValue,
                            exercises: [
                                ProgramExercise(
                                    name: "Squat", exerciseID: nil, sets: 5, repsLow: 5, repsHigh: nil,
                                    weightKg: 100, rpe: nil, percentOf1RM: nil, restSeconds: 180, group: nil, notes: "AMRAP last set"
                                ),
                            ],
                            notes: nil
                        ),
                    ]),
                ],
                autoAssignedWeekdays: false
            )
            reviewPayload = ReviewPayload(
                parsed: sample,
                sourceKind: "text",
                sourceText: "DEBUG sample — no real source text."
            )
        }
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
