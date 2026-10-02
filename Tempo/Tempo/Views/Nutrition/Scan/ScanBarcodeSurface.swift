//
// ScanBarcodeSurface.swift
// Tempo
//
// The one live barcode camera: permission gate, DataScanner viewfinder,
// "type the barcode" fallback, offline hint. Every barcode flow (food,
// pantry, supplements) shows this in its scanning state and gets the number
// back through `onBarcode` — it never looks anything up or saves anything.
//

import SwiftUI
import VisionKit

// MARK: - ScanFallbackAction

/// A button offered when the camera can't be used.
struct ScanFallbackAction: Identifiable {
    let title: String
    let action: () -> Void
    var id: String {
        title
    }
}

// MARK: - ScanBarcodeSurface

struct ScanBarcodeSurface: View {
    var prompt = "Point at a barcode"
    var detail: String?
    /// Shown when the camera is denied/unsupported, after "Type the barcode".
    var fallbackActions: [ScanFallbackAction] = []
    /// Barcode lookups need the network for unknown products; known ones still open.
    var isOffline = false
    var onSearchOffline: (() -> Void)?
    var onBarcode: (String) -> Void

    @Environment(\.scenePhase)
    private var scenePhase
    @State
    private var permission = CameraPermission.current()
    @State
    private var showManualEntry = false
    @State
    private var manualBarcode = ""

    var body: some View {
        Group {
            switch permission {
            case .authorized:
                scanner
            case .notDetermined:
                VStack(spacing: TempoSpacing.lg) {
                    ProgressView().controlSize(.large)
                    Text("Allow the camera to scan.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Button("Allow camera") { Task { await ask() } }
                        .buttonStyle(.tempoPrimary)
                        .padding(.horizontal, TempoSpacing.xxxxl)
                }
            case .denied,
                 .restricted,
                 .unsupported:
                blocked
            }
        }
        .task {
            // The Scan tap that opened this is the first moment we need it.
            if permission == .notDetermined {
                await ask()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings: pick up the new answer.
            if phase == .active {
                permission = CameraPermission.current()
            }
        }
        .alert("Type the barcode", isPresented: $showManualEntry) {
            TextField("e.g. 8000500310427", text: $manualBarcode)
                .keyboardType(.numberPad)
            Button("Look up") {
                let code = manualBarcode
                manualBarcode = ""
                onBarcode(code)
            }
            Button("Cancel", role: .cancel) { manualBarcode = "" }
        } message: {
            Text("The numbers under the barcode.")
        }
    }

    private func ask() async {
        permission = await CameraPermission.request()
    }

    // MARK: - Live scanner

    private var scanner: some View {
        ZStack {
            ScanBarcodeCamera(onBarcode: onBarcode)
                .ignoresSafeArea()

            VStack {
                if isOffline {
                    offlineBanner
                }
                Spacer()
                RoundedRectangle(cornerRadius: TempoRadius.xxxxl, style: .continuous)
                    .strokeBorder(Color.tempoSignal, lineWidth: 3)
                    .frame(width: 280, height: 180)
                Spacer()
                VStack(spacing: TempoSpacing.sm) {
                    Text(prompt)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoBone)
                    if let detail {
                        Text(detail)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoBone.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    Button("Type the barcode instead") { showManualEntry = true }
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoSignal)
                        .padding(.top, TempoSpacing.xs)
                        .accessibilityIdentifier("scanTypeBarcode")
                }
                .padding(.horizontal, TempoSpacing.xxl)
                .padding(.vertical, TempoSpacing.lg)
                .background(Color.tempoInk.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                .padding(.horizontal, TempoSpacing.lg)
                .padding(.bottom, TempoSpacing.xxxxl)
            }
        }
    }

    /// Inline, not an alert: it must never cover a product you're reading.
    private var offlineBanner: some View {
        VStack(spacing: TempoSpacing.xs) {
            Text("You're offline. Products you've checked before still open from your history.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoBone)
                .multilineTextAlignment(.center)
            if let onSearchOffline {
                Button("Search basic foods", action: onSearchOffline)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSignal)
            }
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoInk.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.top, TempoSpacing.sm)
        .accessibilityIdentifier("scanOfflineBanner")
    }

    // MARK: - Denied / unsupported

    private var blocked: some View {
        let isUnsupported = permission == .unsupported
        return VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Image(systemName: isUnsupported ? "camera.metering.unknown" : "camera.fill")
                .font(.tempoScoreDisplay)
                .foregroundStyle(Color.tempoAsh)
            Text(Self.title(for: permission))
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(Self.message(for: permission))
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            VStack(spacing: TempoSpacing.buttonStackVertical) {
                if permission == .denied {
                    Button("Open Settings") { CameraPermission.openSettings() }
                        .buttonStyle(.tempoPrimary)
                        .accessibilityIdentifier("scanOpenSettings")
                }
                if permission == .denied {
                    Button("Type the barcode") { showManualEntry = true }
                        .buttonStyle(.tempoSecondary)
                        .accessibilityIdentifier("scanTypeBarcode")
                } else {
                    Button("Type the barcode") { showManualEntry = true }
                        .buttonStyle(.tempoPrimary)
                        .accessibilityIdentifier("scanTypeBarcode")
                }
                ForEach(fallbackActions) { fallback in
                    Button(fallback.title, action: fallback.action)
                        .buttonStyle(.tempoGhost)
                }
            }
            .padding(.horizontal, TempoSpacing.xxxxl)
            Spacer()
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .accessibilityIdentifier(isUnsupported ? "scanUnsupported" : "scanPermissionBlocked")
    }

    static func title(for permission: CameraPermission) -> String {
        switch permission {
        case .denied: "Camera is off for Tempo"
        case .restricted: "Camera is restricted"
        default: "Camera scanning unavailable"
        }
    }

    static func message(for permission: CameraPermission) -> String {
        switch permission {
        case .denied: "Turn the camera on in Settings to scan. You can still type the numbers under the barcode."
        case .restricted: "This device doesn't let Tempo use the camera. You can still type the numbers under the barcode."
        default: "This device can't scan barcodes. Type the numbers under the barcode instead."
        }
    }
}

// MARK: - ScanBarcodeCamera

struct ScanBarcodeCamera: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean8, .ean13, .upce, .code128]),
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: ScanBarcodeCamera
        private var hasScanned = false

        init(_ parent: ScanBarcodeCamera) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else {
                return
            }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    hasScanned = true
                    dataScanner.stopScanning()
                    Task { @MainActor in
                        self.parent.onBarcode(payload)
                    }
                    return
                }
            }
        }
    }
}
