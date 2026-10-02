//
// BarcodeScannerView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI
import VisionKit

// MARK: - BarcodeScannerView

// VisionKit DataScannerViewController → FoodCatalog lookup (your own added
// products, then Open Food Facts) → the product screen with its Tempo score.
// With `onFoodScanned` it's part of meal logging ("Add to meal"); without it
// it's scan-to-check — nothing is logged. Unknown barcodes can be added.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct BarcodeScannerView: View {
    var onFoodScanned: ((FoodItem) -> Void)?

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var scanState: ScanState = .scanning
    @State
    private var showManualEntry = false
    @State
    private var manualBarcode = ""
    @State
    private var showAddProduct = false
    @State
    private var showSearch = false
    @State
    private var catalog: FoodCatalog?
    @State
    private var network = NetworkStatus()
    @State
    private var showOfflineNotice = false

    private enum ScanState: Equatable {
        case scanning
        case loading(String)
        case found(FoodProduct)
        case notFound(String)
        case failed(barcode: String, message: String)
        case unavailable
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary
                    .ignoresSafeArea()

                switch scanState {
                case .scanning:
                    scannerContent
                case .loading:
                    loadingContent
                case let .found(product):
                    if let catalog {
                        FoodProductView(product: product, mode: productMode, catalog: catalog, recordsView: false)
                            .id(product.id)
                    }
                case let .notFound(barcode):
                    notFoundContent(barcode)
                case let .failed(barcode, message):
                    failedContent(barcode: barcode, message: message)
                case .unavailable:
                    scannerUnavailableContent
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(onFoodScanned == nil ? "Done" : "Cancel") {
                        dismiss()
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
                if case .found = scanState {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            resetScanner()
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                        .accessibilityLabel("Scan another")
                        .accessibilityIdentifier("scanAnother")
                    }
                }
            }
            .navigationDestination(isPresented: $showAddProduct) {
                if let catalog {
                    AddProductView(barcode: currentBarcode, catalog: catalog) { product in
                        showAddProduct = false
                        scanState = .found(product)
                    }
                }
            }
            .alert("Type the barcode", isPresented: $showManualEntry) {
                TextField("e.g. 8000500310427", text: $manualBarcode)
                    .keyboardType(.numberPad)
                Button("Look up") {
                    let code = manualBarcode
                    manualBarcode = ""
                    lookUp(code)
                }
                Button("Cancel", role: .cancel) {
                    manualBarcode = ""
                }
            } message: {
                Text("The numbers under the barcode.")
            }
            .sheet(isPresented: $showSearch) {
                FoodSearchView(onFoodSelected: onFoodScanned.map { handler in
                    { item in
                        handler(item)
                        dismiss()
                    }
                })
            }
            .alert("You're offline", isPresented: $showOfflineNotice) {
                Button("Search basic foods") {
                    showSearch = true
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Barcode scanning needs internet to look products up. Products you've checked before still open from your history.")
            }
            .onAppear {
                if catalog == nil {
                    catalog = FoodCatalog(services: services)
                }
                checkScannerAvailability()
            }
            .task {
                await network.monitor()
            }
            .onChange(of: network.isOffline) { _, offline in
                showOfflineNotice = offline
            }
        }
    }

    private var productMode: FoodProductView.Mode {
        guard let onFoodScanned else {
            return .check
        }
        return .log { item in
            onFoodScanned(item)
            dismiss()
        }
    }

    private var navigationTitle: String {
        if case .found = scanState {
            return ""
        }
        return onFoodScanned == nil ? "Check a Product" : "Scan Barcode"
    }

    private var currentBarcode: String? {
        switch scanState {
        case let .notFound(code), let .loading(code), let .failed(code, _): code
        case let .found(product): product.barcode
        default: nil
        }
    }

    // MARK: - Scanner Content

    private var scannerContent: some View {
        ZStack {
            BarcodeScannerRepresentable { barcode in
                lookUp(barcode)
            }
            .ignoresSafeArea()

            scanningOverlay
        }
    }

    private var scanningOverlay: some View {
        VStack {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: TempoRadius.xxxxl, style: .continuous)
                    .strokeBorder(Color.tempoSignal, lineWidth: 3)
                    .frame(width: 280, height: 180)
                scannerCornerAccents
            }

            Spacer()

            VStack(spacing: TempoSpacing.sm) {
                Text("Point at a barcode")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoBone)
                Text("Instant score: nutrition, additives, what it means for you today.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoBone.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("Type the barcode instead") {
                    showManualEntry = true
                }
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoSignal)
                .padding(.top, TempoSpacing.xs)
            }
            .padding(.horizontal, TempoSpacing.xxl)
            .padding(.vertical, TempoSpacing.lg)
            .background(Color.tempoInk.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.xxxxl)
        }
    }

    private var scannerCornerAccents: some View {
        ZStack {
            cornerAccent(rotation: 0)
                .offset(x: -130, y: -80)
            cornerAccent(rotation: 90)
                .offset(x: 130, y: -80)
            cornerAccent(rotation: 180)
                .offset(x: 130, y: 80)
            cornerAccent(rotation: 270)
                .offset(x: -130, y: 80)
        }
    }

    private func cornerAccent(rotation: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(Color.tempoSignal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: 20, height: 20)
        .rotationEffect(.degrees(rotation))
    }

    // MARK: - Loading

    private var loadingContent: some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Looking up product…")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Not found

    private func notFoundContent(_ barcode: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "barcode.viewfinder")
                .font(.tempoScoreDisplay)
                .foregroundStyle(Color.tempoAsh)

            Text("Not in the database yet")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(.top, TempoSpacing.lg)

            Text("Barcode \(barcode). Add it once with two photos — every scan after that is instant.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, TempoSpacing.sm)

            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button("Add this product") {
                    showAddProduct = true
                }
                .buttonStyle(.tempoPrimary)
                .accessibilityIdentifier("addMissingProduct")

                Button("Search by name") {
                    showSearch = true
                }
                .buttonStyle(.tempoSecondary)

                Button("Scan again") {
                    resetScanner()
                }
                .buttonStyle(.tempoGhost)
            }
            .padding(.horizontal, TempoSpacing.xxxxl)
            .padding(.top, TempoSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Failed

    private func failedContent(barcode: String, message: String) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.tempoScoreDisplay)
                .foregroundStyle(Color.tempoAsh)
            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)
            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button("Try again") {
                    lookUp(barcode)
                }
                .buttonStyle(.tempoPrimary)
                Button("Scan again") {
                    resetScanner()
                }
                .buttonStyle(.tempoSecondary)
            }
            .padding(.horizontal, TempoSpacing.xxxxl)
            Spacer()
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Scanner Unavailable

    private var scannerUnavailableContent: some View {
        VStack(spacing: TempoSpacing.lg) {
            EmptyStateView(
                icon: "camera.fill",
                title: "Camera scanning unavailable",
                message: "Type the numbers under the barcode, or search by name.",
                actionTitle: "Type the barcode"
            ) {
                showManualEntry = true
            }
            Button("Search by name") {
                showSearch = true
            }
            .buttonStyle(.tempoGhost)
        }
    }

    // MARK: - Actions

    private func checkScannerAvailability() {
        guard scanState == .scanning else {
            return
        }
        if !DataScannerViewController.isSupported || !DataScannerViewController.isAvailable {
            scanState = .unavailable
        }
    }

    private func lookUp(_ barcode: String) {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty, let catalog else {
            return
        }
        if case .loading = scanState {
            return
        }
        scanState = .loading(code)
        HapticManager.mediumImpact()
        Task {
            switch await catalog.lookUp(barcode: code, in: modelContext) {
            case let .found(product):
                HapticManager.success()
                scanState = .found(product)
            case let .notFound(code):
                HapticManager.warning()
                scanState = .notFound(code)
            case let .failed(message):
                HapticManager.error()
                scanState = .failed(barcode: code, message: message)
            }
        }
    }

    private func resetScanner() {
        scanState = .scanning
        checkScannerAvailability()
    }
}

// MARK: - BarcodeScannerRepresentable

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    var onBarcodeScanned: (String) -> Void

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

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScannerRepresentable
        private var hasScanned = false

        init(_ parent: BarcodeScannerRepresentable) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else {
                return
            }

            for item in addedItems {
                if case let .barcode(barcode) = item {
                    if let payload = barcode.payloadStringValue {
                        hasScanned = true
                        dataScanner.stopScanning()

                        Task { @MainActor in
                            self.parent.onBarcodeScanned(payload)
                        }
                        return
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BarcodeScannerView()
        .environment(ServiceContainer.mock())
        .modelContainer(for: [ScannedFood.self], inMemory: true)
}
