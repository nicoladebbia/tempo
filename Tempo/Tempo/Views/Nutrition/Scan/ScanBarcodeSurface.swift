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
                KitchenStatePage(actions: [
                    KitchenStateAction(title: "Allow camera", systemImage: "camera.fill", role: .primary) {
                        Task { await ask() }
                    },
                ]) {
                    KitchenStateHero(
                        systemImage: "camera.fill",
                        title: "Allow the camera to scan.",
                        message: "Tempo reads the barcode with the camera."
                    )
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
                .kitchenScrim()
            // Same container as the scrim's window, so the brackets sit exactly on it.
            KitchenFrame()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            // The prompt hangs right under the window it talks about.
            Color.clear
                .frame(width: Tide.Kitchen.viewfinderWidth, height: Tide.Kitchen.viewfinderHeight)
                .overlay(alignment: .bottom) {
                    promptPanel
                        .alignmentGuide(.bottom) { $0[.top] - Tide.s5 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                if isOffline {
                    offlineBanner
                }
                Spacer()
                // The one control sits in the thumb zone, full width.
                Button {
                    showManualEntry = true
                } label: {
                    Label("Type the barcode instead", systemImage: "keyboard")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .frame(maxWidth: .infinity, minHeight: Tide.Kitchen.barButton)
                        .glassEffect(.regular.tint(Tide.Kitchen.cameraTint).interactive(), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s10)
                .accessibilityIdentifier("scanTypeBarcode")
            }
        }
    }

    private var promptPanel: some View {
        VStack(spacing: Tide.s1) {
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
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .kitchenCameraPanel(radius: Tide.tileRadius)
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
        var actions: [KitchenStateAction] = []
        if permission == .denied {
            actions.append(KitchenStateAction(title: "Open Settings", role: .primary, identifier: "scanOpenSettings") {
                if let info = resumeInfo {
                    ScanResume.save(kind: info.kind, mode: info.mode, section: info.section)
                }
                CameraPermission.openSettings()
            })
        }
        actions.append(KitchenStateAction(
            title: "Type the barcode",
            systemImage: "keyboard",
            role: permission == .denied ? .secondary : .primary,
            identifier: "scanTypeBarcode"
        ) { showManualEntry = true })
        for fallback in fallbackActions {
            actions.append(KitchenStateAction(title: fallback.title, role: .secondary, action: fallback.action))
        }
        return KitchenStatePage(actions: actions) {
            KitchenStateHero(
                systemImage: isUnsupported ? "camera.metering.unknown" : "camera.fill",
                tint: isUnsupported ? Tide.text3 : Tide.Kitchen.warn,
                title: Self.title(for: permission),
                message: Self.message(for: permission)
            )
        }
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
