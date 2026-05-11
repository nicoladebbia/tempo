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

// MARK: - ReceiptCaptureView

struct ReceiptCaptureView: View {
    let receiptService: any ReceiptServiceProtocol
    let pantryService: any PantryServiceProtocol

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var selectedImage: UIImage?
    @State
    private var isShowingPicker = false
    @State
    private var pickerSource: PickerSource = .camera
    @State
    private var isScanning = false
    @State
    private var scanError: String?
    @State
    private var scannedReceipt: Receipt?

    enum PickerSource { case camera, library }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary.ignoresSafeArea()
                if let receipt = scannedReceipt {
                    NavigationLink(
                        destination: ReceiptReviewView(
                            receipt: receipt,
                            receiptService: receiptService,
                            pantryService: pantryService
                        ).onDisappear { dismiss() },
                        isActive: .constant(true)
                    ) {
                        EmptyView()
                    }
                    .hidden()
                } else if isScanning {
                    scanningOverlay
                } else {
                    captureOptions
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingPicker) {
                ImagePicker(sourceType: pickerSource == .camera ? .camera : .photoLibrary) { image in
                    isShowingPicker = false
                    selectedImage = image
                    if let image {
                        scan(image)
                    }
                }
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

            if let scanError {
                Text(scanError)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.xl)
            }

            VStack(spacing: TempoSpacing.md) {
                Button {
                    pickerSource = .camera
                    isShowingPicker = true
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

    private var scanningOverlay: some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView().scaleEffect(1.4)
            Text("Reading the receipt...")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Scan

    private func scan(_ image: UIImage) {
        scanError = nil
        isScanning = true
        Task {
            do {
                let receipt = try await receiptService.scan(image: image, storeHint: nil)
                scannedReceipt = receipt
            } catch {
                scanError = error.localizedDescription
                Logger.nutrition.error("Receipt scan failed: \(error.localizedDescription, privacy: .public)")
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
