//
// ReceiptCaptureView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import os
import SwiftUI
import UIKit
import VisionKit

// MARK: - ReceiptCaptureView

struct ReceiptCaptureView: View {
    let receiptService: any ReceiptServiceProtocol
    let pantryService: any PantryServiceProtocol
    /// Forwarded to ReceiptReviewView — fires after ingest so the pantry add
    /// re-deducts from the active grocery list.
    var onIngested: (() -> Void)?

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var selectedImage: UIImage?
    @State
    private var isShowingPicker = false
    @State
    private var pickerSource: PickerSource = .camera
    @State
    private var isShowingDocumentScanner = false
    @State
    private var isScanning = false
    @State
    private var scanError: String?
    @State
    private var scanBlocker: AIBlocker?
    @State
    private var scannedReceipt: Receipt?
    @State
    private var scanPages: [UIImage] = []
    @State
    private var scanProgress = ReceiptScanProgress()

    enum PickerSource { case camera, library }

    /// VNDocumentCameraViewController (auto-shutter + perspective correction,
    /// native multi-page capture via its own "+" control) isn't available on
    /// every device/simulator — falls back to the single-shot camera picker
    /// when it isn't.
    private var documentScannerAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    /// Embedded in UniversalScanView's NavigationStack (Receipt mode), so this
    /// is a plain `Group`: the destination/title/modifiers below attach to
    /// the scanner's stack, and its toolbar owns Cancel.
    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()
            if isScanning {
                ReceiptProcessingView(images: scanPages, progress: scanProgress)
            } else {
                captureOptions
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { scannedReceipt != nil },
            set: {
                if !$0 {
                    scannedReceipt = nil
                }
            }
        )) {
            if let receipt = scannedReceipt {
                ReceiptReviewView(
                    receipt: receipt,
                    receiptService: receiptService,
                    pantryService: pantryService,
                    onIngested: onIngested
                )
                .onDisappear { dismiss() }
            }
        }
        .navigationTitle("Scan Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingPicker) {
            ImagePicker(sourceType: pickerSource == .camera ? .camera : .photoLibrary) { image in
                isShowingPicker = false
                selectedImage = image
                if let image {
                    scan(image)
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingDocumentScanner) {
            DocumentScannerView { pages in
                isShowingDocumentScanner = false
                guard !pages.isEmpty else {
                    return
                }
                scan(pages)
            }
        }
    }

    // MARK: - Sections

    private var captureOptions: some View {
        VStack(spacing: TempoSpacing.xl) {
            Spacer()
            Image(systemName: "receipt")
                .font(.system(size: 64))
                .foregroundStyle(Color.tempoViolet)

            Text("Snap your receipt")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("On-device OCR plus AI structuring. Review each line before it goes in your pantry.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.xl)

            if documentScannerAvailable {
                Text("Long receipt? Tap + after the first page to add more — they're stitched together automatically.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.xl)
            }

            if let scanBlocker {
                AIBlockerCard(
                    blocker: scanBlocker,
                    message: scanBlocker == .proRequired
                        ? "Reading receipts is a Tempo Pro feature."
                        : "AI features are off. Turn them on to read receipts."
                ) {
                    self.scanBlocker = nil
                    scanError = nil
                }
                .padding(.horizontal, TempoSpacing.xl)
            } else if let scanError {
                Text(scanError)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.xl)
            }

            VStack(spacing: TempoSpacing.md) {
                Button {
                    if documentScannerAvailable {
                        isShowingDocumentScanner = true
                    } else {
                        pickerSource = .camera
                        isShowingPicker = true
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)

                Button {
                    pickerSource = .library
                    isShowingPicker = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            Spacer()
        }
    }

    // MARK: - Scan

    #if DEBUG
        /// QA only (`--uitesting-receipt-slow`): the simulator has no backend,
        /// so replay the pipeline's progress to look at the processing screen.
        private static func debugSlowProgress(_ progress: ReceiptScanProgress) async {
            guard ProcessInfo.processInfo.arguments.contains("--uitesting-receipt-slow") else {
                return
            }
            try? await Task.sleep(for: .seconds(2))
            progress.parsed(store: "Publix", total: 61.37, itemCount: 13)
            progress.advance(to: .findingItems)
            try? await Task.sleep(for: .seconds(30))
        }
    #endif

    private func beginScan(pages: [UIImage]) {
        scanError = nil
        scanBlocker = nil
        scanPages = pages
        scanProgress = ReceiptScanProgress()
        isScanning = true
    }

    private func scan(_ image: UIImage) {
        beginScan(pages: [image])
        let progress = scanProgress
        Task {
            #if DEBUG
                await Self.debugSlowProgress(progress)
            #endif
            do {
                let receipt = try await ReceiptScanProgress.$current.withValue(progress) {
                    try await receiptService.scan(image: image, storeHint: nil)
                }
                progress.finish()
                scannedReceipt = receipt
            } catch {
                scanBlocker = AIBlocker(error)
                scanError = AIBlocker.readableDescription(error)
                Logger.nutrition.error("Receipt scan failed: \(error.localizedDescription, privacy: .public)")
            }
            isScanning = false
        }
    }

    /// Multi-page capture from `DocumentScannerView` — a single-page scan
    /// (the common case) is routed through the exact same
    /// `receiptService.scan(images:)` call, which itself short-circuits back
    /// to the single-image path for one element.
    private func scan(_ images: [UIImage]) {
        beginScan(pages: images)
        let progress = scanProgress
        Task {
            do {
                let receipt = try await ReceiptScanProgress.$current.withValue(progress) {
                    try await receiptService.scan(images: images, storeHint: nil)
                }
                progress.finish()
                scannedReceipt = receipt
            } catch {
                scanBlocker = AIBlocker(error)
                scanError = AIBlocker.readableDescription(error)
                Logger.nutrition.error("Multi-photo receipt scan failed: \(error.localizedDescription, privacy: .public)")
            }
            isScanning = false
        }
    }
}

// MARK: - ImagePicker

private struct ImagePicker: UIViewControllerRepresentable {
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

// MARK: - DocumentScannerView

/// Wraps VNDocumentCameraViewController — native multi-page document
/// capture with auto-shutter (fires as soon as a rectangle is steadily
/// framed) and automatic perspective correction per page. The user can
/// capture as many pages as the receipt needs via the scanner's own "+"
/// control before tapping "Save"; every captured page comes back
/// perspective-corrected and in capture order, which is exactly the input
/// `ReceiptMultiPhotoStitcher` expects.
private struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: VNDocumentCameraViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) {
            self.onFinish = onFinish
        }

        /// Dismissal is driven by the `isShowingDocumentScanner` binding in
        /// ReceiptCaptureView (its `onFinish` closure flips it to false),
        /// exactly like ImagePicker's Coordinator does for `isShowingPicker`
        /// — not a manual `dismiss()` call here, which would fight SwiftUI's
        /// own `fullScreenCover` presentation and trip Swift 6's MainActor
        /// isolation check on a non-Sendable completion closure.
        func documentCameraViewController(_: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var pages: [UIImage] = []
            pages.reserveCapacity(scan.pageCount)
            for pageIndex in 0 ..< scan.pageCount {
                pages.append(scan.imageOfPage(at: pageIndex))
            }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_: VNDocumentCameraViewController, didFailWithError error: Error) {
            Logger.nutrition.error("Document scanner failed: \(error.localizedDescription, privacy: .public)")
            onFinish([])
        }
    }
}
