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
    @Environment(\.tideMood)
    private var mood
    @Environment(ServiceContainer.self)
    private var services

    @State private var model: SupplementLabelPhotoModel?
    @State private var pickerSource: PhotoSource?
    /// The in-flight read; cancelled on Cancel / dismiss so no review sheet pops up later.
    @State private var readTask: Task<Void, Never>?

    private enum PhotoSource: String, Identifiable {
        case camera, library
        var id: String { rawValue }
        var type: UIImagePickerController.SourceType { self == .camera ? .camera : .photoLibrary }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Tide.s4) {
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tide.s6)
            .frame(maxWidth: .infinity)
            .navigationTitle("Read a label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        readTask?.cancel()
                        dismiss()
                    }
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
            .onDisappear { readTask?.cancel() }
            .onAppear {
                if model == nil {
                    model = SupplementLabelPhotoModel(
                        service: injectedService ?? LiveSupplementLookupService(apiClient: services.apiClient),
                        upc: upc
                    )
                }
            }
        }
        .kitchenSheet()
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
        VStack(spacing: Tide.s4) {
            Image(systemName: "text.viewfinder")
                .font(Tide.largeTitle)
                .foregroundStyle(mood.accent)
                .frame(width: 96, height: 96)
                .glassEffect(.regular.tint(Tide.glassCard), in: .circle)
                .accessibilityHidden(true)
            Text("Photograph the label")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            Text("Get the Supplement Facts panel in frame — flat, lit, close. Tempo reads it and you check it before anything is saved.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
            VStack(spacing: Tide.s3) {
                Button {
                    pickerSource = .camera
                } label: {
                    Label("Take a photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tidePrimary)
                .accessibilityIdentifier("supplementLabelTakePhoto")
                Button {
                    pickerSource = .library
                } label: {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("supplementLabelChoosePhoto")
                Button("Type it instead") { onTypeIt() }
                    .buttonStyle(.tideGlass)
            }
            .padding(.top, Tide.s3)
        }
    }

    private var readingContent: some View {
        VStack(spacing: Tide.s4) {
            KitchenHeroDisc(systemImage: "text.viewfinder")
                .background { KitchenListeningRing(active: true) }
                .padding(.vertical, Tide.s5)
            Text("Reading your label…")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            Text("This takes about 10 seconds. Hold tight.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier("supplementLabelReading")
    }

    private func failureContent(_ failure: SupplementLabelPhotoModel.Failure) -> some View {
        VStack(spacing: Tide.s4) {
            KitchenHeroDisc(
                systemImage: failure == .offline ? "wifi.exclamationmark" : "text.viewfinder",
                tint: Tide.Kitchen.warn
            )
            Text(failure == .unreadable ? "Couldn't read that one" : "Couldn't read the label")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            Text(failure.message)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
            if case let .blocked(blocker) = failure {
                AIBlockerCard(blocker: blocker, message: failure.message) {
                    model?.reset()
                }
            }
            VStack(spacing: Tide.s3) {
                if failure.canRetrySamePhoto {
                    Button {
                        retry()
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tidePrimary)
                }
                if failure != .busy {
                    if failure.canRetrySamePhoto {
                        retakeButton.buttonStyle(.tideGlass)
                    } else {
                        retakeButton.buttonStyle(.tidePrimary)
                    }
                }
                if failure == .busy {
                    typeItButton.buttonStyle(.tidePrimary)
                } else {
                    typeItButton.buttonStyle(.tideGlass)
                }
            }
            .padding(.top, Tide.s2)
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
        readTask?.cancel()
        readTask = Task {
            await model.read(image: image)
            guard !Task.isCancelled else { return }
            deliver(model)
        }
    }

    private func retry() {
        guard let model else { return }
        readTask?.cancel()
        readTask = Task {
            await model.retry()
            guard !Task.isCancelled else { return }
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
