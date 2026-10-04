//
// SupplementLabelCaptureSheet.swift
// Tempo
//
// "Photograph the label": take a photo (or pick one), Tempo's AI reads the
// Supplement Facts and front of pack, and the caller opens the normal review
// screen prefilled with the result. Reachable from the barcode not-found
// fallback, the shelf's Add menu and the search sheet's empty state. Never a
// dead end: every failure offers a way forward (retake, retry, type it).
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftUI

struct SupplementLabelCaptureSheet: View {
    /// Barcode that led here, if any — rides along so the read-out keeps it.
    let upc: String?
    /// Called with the AI read-out. The caller swaps this sheet for the review
    /// screen (the sheet does not dismiss itself).
    let onResult: (SupplementLookupDTO) -> Void
    /// "Type it instead" — the caller opens the blank form.
    let onTypeIt: () -> Void
    var injectedService: (any SupplementLookupServicing)?

    @Environment(\.dismiss)
    private var dismiss
    @Environment(ServiceContainer.self)
    private var services

    @State private var model: SupplementLabelPhotoModel?
    @State private var pickerSource: PhotoSource?

    private enum PhotoSource: String, Identifiable {
        case camera, library
        var id: String { rawValue }
        var type: UIImagePickerController.SourceType { self == .camera ? .camera : .photoLibrary }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.lg) {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TempoSpacing.xxl)
            .frame(maxWidth: .infinity)
            .background(Color.tempoBgPrimary.ignoresSafeArea())
            .navigationTitle("Read a label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(item: $pickerSource) { source in
                FoodImagePicker(sourceType: source.type) { image in
                    pickerSource = nil
                    if let image {
                        start(image)
                    }
                }
                .ignoresSafeArea()
            }
            .onAppear {
                if model == nil {
                    model = SupplementLabelPhotoModel(
                        service: injectedService ?? LiveSupplementLookupService(apiClient: services.apiClient),
                        upc: upc
                    )
                }
            }
        }
        .interactiveDismissDisabled(model?.state == .reading)
    }

    @ViewBuilder
    private var content: some View {
        switch model?.state ?? .idle {
        case .idle:
            idleContent
        case .reading, .done:
            readingContent
        case let .failed(failure):
            failureContent(failure)
        }
    }

    private var idleContent: some View {
        VStack(spacing: TempoSpacing.lg) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.tempoSignal)
            Text("Photograph the label")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Get the Supplement Facts panel in frame — flat, lit, close. Tempo reads it and you check it before anything is saved.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button {
                    pickerSource = .camera
                } label: {
                    Label("Take a photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                .accessibilityIdentifier("supplementLabelTakePhoto")
                Button {
                    pickerSource = .library
                } label: {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
                .accessibilityIdentifier("supplementLabelChoosePhoto")
                Button("Type it instead") { onTypeIt() }
                    .buttonStyle(.tempoGhost)
            }
            .padding(.top, TempoSpacing.md)
        }
    }

    private var readingContent: some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView().controlSize(.large)
            Text("Reading your label…")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("This takes about 10 seconds. Hold tight.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier("supplementLabelReading")
    }

    private func failureContent(_ failure: SupplementLabelPhotoModel.Failure) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Image(systemName: failure == .offline ? "wifi.exclamationmark" : "text.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoAsh)
            Text(failure == .unreadable ? "Couldn't read that one" : "Couldn't read the label")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(failure.message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            if case let .blocked(blocker) = failure {
                AIBlockerCard(blocker: blocker, message: failure.message) {
                    model?.reset()
                }
            }
            VStack(spacing: TempoSpacing.buttonStackVertical) {
                if failure.canRetrySamePhoto {
                    Button {
                        retry()
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tempoPrimary)
                }
                if failure != .busy {
                    if failure.canRetrySamePhoto {
                        retakeButton.buttonStyle(.tempoSecondary)
                    } else {
                        retakeButton.buttonStyle(.tempoPrimary)
                    }
                }
                if failure == .busy {
                    typeItButton.buttonStyle(.tempoPrimary)
                } else {
                    typeItButton.buttonStyle(.tempoSecondary)
                }
            }
            .padding(.top, TempoSpacing.sm)
        }
    }

    private var typeItButton: some View {
        Button {
            onTypeIt()
        } label: {
            Label("Type it", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("supplementLabelTypeIt")
    }

    private var retakeButton: some View {
        Button {
            model?.reset()
            pickerSource = .camera
        } label: {
            Label("Retake", systemImage: "camera")
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("supplementLabelRetake")
    }

    // MARK: - Actions

    private func start(_ image: UIImage) {
        guard let model else { return }
        Task {
            await model.read(image: image)
            deliver(model)
        }
    }

    private func retry() {
        guard let model else { return }
        Task {
            await model.retry()
            deliver(model)
        }
    }

    private func deliver(_ model: SupplementLabelPhotoModel) {
        if case let .done(dto) = model.state {
            HapticManager.success()
            onResult(dto)
        } else {
            HapticManager.warning()
        }
    }
}
