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
    @Environment(\.scanResumeInfo)
    private var resumeInfo
    @State
    private var permission = CameraPermission.current()
    @State
    private var showManualEntry = false
    @State
    private var manualBarcode = ""
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Group {
            switch permission {
            case .authorized:
                scanner
            case .notDetermined:
                VStack(spacing: Tide.s4) {
                    ProgressView().controlSize(.large).tint(mood.accent)
                    Text("Allow the camera to scan.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                    Button("Allow camera") { Task { await ask() } }
                        .buttonStyle(.tidePrimary)
                }
                .padding(Tide.s6)
                .kitchenCameraPanel()
                .padding(.horizontal, Tide.edge)
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
        // Back from Settings: pick up the new answer and start the camera
        // without another tap. `.task(id:)` re-runs on every return to .active
        // and cancels a still-running re-check; nothing here resets the scan.
        .task(id: scenePhase) {
            guard scenePhase == .active, permission != .notDetermined else {
                return
            }
            let fresh = await CameraPermission.recheckAfterForeground()
            if fresh != permission {
                permission = fresh
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
                RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                    .strokeBorder(mood.accent, lineWidth: 3)
                    .frame(width: Tide.Kitchen.viewfinderWidth, height: Tide.Kitchen.viewfinderHeight)
                    .accessibilityHidden(true)
                Spacer()
                VStack(spacing: Tide.s2) {
                    Text(prompt)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                    if let detail {
                        Text(detail)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.center)
                    }
                    Button("Type the barcode instead") { showManualEntry = true }
                        .font(Tide.bodyStrong)
                        .foregroundStyle(mood.accent)
                        .frame(minHeight: Tide.hit)
                        .accessibilityIdentifier("scanTypeBarcode")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Tide.s5)
                .padding(.vertical, Tide.s4)
                .kitchenCameraPanel()
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s10)
            }
        }
    }

    /// Inline, not an alert: it must never cover a product you're reading.
    private var offlineBanner: some View {
        VStack(spacing: Tide.s1) {
            Text("You're offline. Products you've checked before still open from your history.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
            if let onSearchOffline {
                Button("Search basic foods", action: onSearchOffline)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(mood.accent)
                    .frame(minHeight: Tide.hit)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Tide.s3)
        .kitchenCameraPanel(radius: Tide.tileRadius)
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s2)
        .accessibilityIdentifier("scanOfflineBanner")
    }

    // MARK: - Denied / unsupported

    private var blocked: some View {
        let isUnsupported = permission == .unsupported
        return VStack(spacing: Tide.s4) {
            Spacer()
            VStack(spacing: Tide.s4) {
                Image(systemName: isUnsupported ? "camera.metering.unknown" : "camera.fill")
                    .font(Tide.largeTitle)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
                Text(Self.title(for: permission))
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                Text(Self.message(for: permission))
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Tide.s3) {
                    if permission == .denied {
                        Button("Open Settings") {
                            if let info = resumeInfo {
                                ScanResume.save(kind: info.kind, mode: info.mode, section: info.section)
                            }
                            CameraPermission.openSettings()
                        }
                        .buttonStyle(.tidePrimary)
                        .accessibilityIdentifier("scanOpenSettings")
                    }
                    if permission == .denied {
                        Button("Type the barcode") { showManualEntry = true }
                            .buttonStyle(.tideGlass)
                            .accessibilityIdentifier("scanTypeBarcode")
                    } else {
                        Button("Type the barcode") { showManualEntry = true }
                            .buttonStyle(.tidePrimary)
                            .accessibilityIdentifier("scanTypeBarcode")
                    }
                    ForEach(fallbackActions) { fallback in
                        Button(fallback.title, action: fallback.action)
                            .buttonStyle(.tideGlass)
                    }
                }
                .padding(.top, Tide.s2)
            }
            .frame(maxWidth: .infinity)
            .tideCard(padding: Tide.s6)
            Spacer()
        }
        .padding(.horizontal, Tide.edge)
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
