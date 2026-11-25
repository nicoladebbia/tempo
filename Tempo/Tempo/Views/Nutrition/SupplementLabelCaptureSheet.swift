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
            content
                .animation(Tide.snap, value: model?.state)
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
        KitchenStatePage(actions: [
            KitchenStateAction(
                title: String(localized: "Take a photo"), systemImage: "camera", role: .primary,
                identifier: "supplementLabelTakePhoto"
            ) {
                pickerSource = .camera
            },
            KitchenStateAction(
                title: String(localized: "Choose from library"), systemImage: "photo.on.rectangle",
                identifier: "supplementLabelChoosePhoto"
            ) {
                pickerSource = .library
            },
            KitchenStateAction(title: String(localized: "Type it instead"), role: .quiet) {
                onTypeIt()
            },
        ]) {
            VStack(spacing: Tide.s5) {
                KitchenStateHero(
                    systemImage: "text.viewfinder",
                    title: String(localized: "Photograph the label"),
                    message: String(localized: "Get the Supplement Facts panel in frame. Tempo reads it and you check it before anything is saved.")
                )
                VStack(alignment: .leading, spacing: Tide.s3) {
                    tip("rectangle.portrait", String(localized: "Hold it flat, the whole panel in frame"))
                    tip("sun.max", String(localized: "Good light, no glare on the print"))
                    tip("viewfinder", String(localized: "Close enough that the small print is sharp"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
        }
    }

    private func tip(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
            Image(systemName: systemImage)
                .font(Tide.bodyStrong)
                .foregroundStyle(mood.accent)
                .frame(width: Tide.icon)
                .accessibilityHidden(true)
            Text(text)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readingContent: some View {
        KitchenStatePage {
            KitchenStateHero(
                systemImage: "text.viewfinder",
                title: String(localized: "Reading your label…"),
                message: String(localized: "This takes about 10 seconds. Hold tight."),
                working: true
            )
            .accessibilityIdentifier("supplementLabelReading")
        }
    }

    private func failureContent(_ failure: SupplementLabelPhotoModel.Failure) -> some View {
        KitchenStatePage(actions: failureActions(failure)) {
            VStack(spacing: Tide.s5) {
                KitchenStateHero(
                    systemImage: failure == .offline ? "wifi.exclamationmark" : "text.viewfinder",
                    tint: Tide.Kitchen.warn,
                    title: failure == .unreadable ? String(localized: "Couldn't read that one") : String(localized: "Couldn't read the label"),
                    // The blocker card below carries the same line.
                    message: failure.isBlocked ? "" : failure.message
                )
                if case let .blocked(blocker) = failure {
                    AIBlockerCard(blocker: blocker, message: failure.message) {
                        model?.reset()
                    }
                }
            }
        }
    }

    /// Every failure keeps a way forward: try the same photo again, retake it,
    /// or type it. The one that fits best is the bar button.
    private func failureActions(_ failure: SupplementLabelPhotoModel.Failure) -> [KitchenStateAction] {
        var actions: [KitchenStateAction] = []
        if failure.canRetrySamePhoto {
            actions.append(KitchenStateAction(title: String(localized: "Try again"), systemImage: "arrow.clockwise", role: .primary) {
                retry()
            })
        }
        if failure != .busy {
            actions.append(KitchenStateAction(
                title: String(localized: "Retake"), systemImage: "camera",
                role: failure.canRetrySamePhoto ? .secondary : .primary,
                identifier: "supplementLabelRetake"
            ) {
                model?.reset()
                pickerSource = .camera
            })
        }
        actions.append(KitchenStateAction(
            title: String(localized: "Type it"), systemImage: "square.and.pencil",
            role: failure == .busy ? .primary : .secondary,
            identifier: "supplementLabelTypeIt"
        ) {
            onTypeIt()
        })
        return actions
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

private extension SupplementLabelPhotoModel.Failure {
    var isBlocked: Bool {
        if case .blocked = self {
            return true
        }
        return false
    }
}
