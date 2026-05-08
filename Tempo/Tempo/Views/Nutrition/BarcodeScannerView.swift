//
// BarcodeScannerView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import SwiftUI
import VisionKit

// MARK: - BarcodeScannerView

// VisionKit DataScannerViewController wrapper for food product barcode scanning.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct BarcodeScannerView: View {
    var onFoodScanned: ((FoodItem) -> Void)?

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var scanState: ScanState = .scanning
    @State
    private var scannedProduct: ScannedProduct?
    @State
    private var portionQuantity: Double = 1.0

    private enum ScanState {
        case scanning
        case loading
        case found
        case notFound
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

                case .found:
                    if let product = scannedProduct {
                        productFoundContent(product)
                    }

                case .notFound:
                    notFoundContent

                case .unavailable:
                    scannerUnavailableContent
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .onAppear {
                checkScannerAvailability()
            }
        }
    }

    // MARK: - Scanner Content

    private var scannerContent: some View {
        ZStack {
            // Scanner view
            BarcodeScannerRepresentable { barcode in
                handleScannedBarcode(barcode)
            }
            .ignoresSafeArea()

            // Scanning overlay
            scanningOverlay
        }
    }

    private var scanningOverlay: some View {
        VStack {
            Spacer()

            // Scanning frame
            ZStack {
                // Semi-transparent background with cutout
                RoundedRectangle(cornerRadius: TempoRadius.xxxxl, style: .continuous)
                    .strokeBorder(Color.tempoSignal, lineWidth: 3)
                    .frame(width: 280, height: 180)

                // Corner accents
                scannerCornerAccents
            }

            Spacer()

            // Instruction label
            VStack(spacing: TempoSpacing.sm) {
                Text("Point at a barcode")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoBone)

                Text("EAN-8, EAN-13, UPC-E, Code 128")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoBone.opacity(0.7))
            }
            .padding(.horizontal, TempoSpacing.xxl)
            .padding(.vertical, TempoSpacing.lg)
            .background(Color.tempoInk.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            .padding(.bottom, TempoSpacing.xxxxl)
        }
    }

    private var scannerCornerAccents: some View {
        ZStack {
            // Top-left
            cornerAccent(rotation: 0)
                .offset(x: -130, y: -80)

            // Top-right
            cornerAccent(rotation: 90)
                .offset(x: 130, y: -80)

            // Bottom-right
            cornerAccent(rotation: 180)
                .offset(x: 130, y: 80)

            // Bottom-left
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

    // MARK: - Loading Content

    private var loadingContent: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(Color.tempoSignal)

            Text("Looking up product...")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            Spacer()
        }
    }

    // MARK: - Product Found Content

    private func productFoundContent(_ product: ScannedProduct) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Product card
                productCard(product)

                // Serving picker
                servingPicker

                // Macro breakdown
                macroBreakdownCard(product)

                // Add button
                Button {
                    addToMeal(product: product)
                } label: {
                    Text("Add to Meal")
                }
                .buttonStyle(.tempoPrimary)
                .padding(.horizontal, TempoSpacing.screenEdge)

                // Scan another
                Button("Scan Another") {
                    resetScanner()
                }
                .buttonStyle(.tempoGhost)
                .padding(.horizontal, TempoSpacing.screenEdge)
            }
            .padding(.top, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.bottomSafe)
        }
    }

    private func productCard(_ product: ScannedProduct) -> some View {
        VStack(spacing: TempoSpacing.md) {
            // Product image placeholder
            if let imageName = product.imageName {
                Image(systemName: imageName)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(width: 120, height: 120)
                    .background(Color.tempoBgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            }

            Text(product.name)
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)

            if let brand = product.brand {
                Text(brand)
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Text("\(product.caloriesPerServing) kcal per \(product.servingSize)")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private var servingPicker: some View {
        VStack(spacing: TempoSpacing.sm) {
            Text("SERVINGS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.moduleTag)
                .foregroundStyle(Color.tempoTextSecondary)

            NumberStepperView(
                value: $portionQuantity,
                range: 0.5 ... 10,
                step: 0.5,
                format: "%.1f",
                unit: "x"
            )
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private func macroBreakdownCard(_ product: ScannedProduct) -> some View {
        let multiplier = portionQuantity

        return VStack(spacing: TempoSpacing.md) {
            HStack {
                Text("Calories")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text("\(Int(Double(product.caloriesPerServing) * multiplier)) kcal")
                    .font(.tempoDataMedium)
                    .foregroundStyle(Color.tempoViolet)
            }

            Divider().background(Color.tempoDivider)

            macroRow(
                label: "Protein",
                value: product.proteinPerServing * multiplier,
                color: Color.tempoMacroProtein
            )
            macroRow(
                label: "Carbs",
                value: product.carbsPerServing * multiplier,
                color: Color.tempoMacroCarbs
            )
            macroRow(
                label: "Fat",
                value: product.fatPerServing * multiplier,
                color: Color.tempoMacroFat
            )
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private func macroRow(label: String, value: Double, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Text("\(Int(value))g")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Not Found Content

    private var notFoundContent: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)

            Text("Product not found")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(.top, TempoSpacing.lg)

            Text("Try manual search.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.top, TempoSpacing.sm)

            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button("Search Manually") {
                    // In production, would present FoodSearchView
                    dismiss()
                }
                .buttonStyle(.tempoPrimary)

                Button("Scan Again") {
                    resetScanner()
                }
                .buttonStyle(.tempoSecondary)
            }
            .padding(.horizontal, TempoSpacing.xxxxl)
            .padding(.top, TempoSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Scanner Unavailable

    private var scannerUnavailableContent: some View {
        EmptyStateView(
            icon: "camera.fill",
            title: "Scanner unavailable",
            message: "This device does not support barcode scanning. Use manual search instead.",
            actionTitle: "Search Manually"
        ) {
            dismiss()
        }
    }

    // MARK: - Actions

    private func checkScannerAvailability() {
        if !DataScannerViewController.isSupported || !DataScannerViewController.isAvailable {
            scanState = .unavailable
        }
    }

    private func handleScannedBarcode(_ barcode: String) {
        guard scanState == .scanning else {
            return
        }
        scanState = .loading
        HapticManager.mediumImpact()

        // Simulated OpenFoodFacts lookup
        Task {
            try? await Task.sleep(for: .seconds(1.5))

            // Mock: 70% chance of finding a product
            if Int.random(in: 0 ... 9) < 7 {
                scannedProduct = ScannedProduct(
                    barcode: barcode,
                    name: "Skyr High Protein",
                    brand: "Arla",
                    servingSize: "150g",
                    caloriesPerServing: 95,
                    proteinPerServing: 15,
                    carbsPerServing: 6,
                    fatPerServing: 0.2,
                    imageName: "takeoutbag.and.cup.and.straw"
                )
                scanState = .found
                HapticManager.notification(.success)
            } else {
                scanState = .notFound
                HapticManager.notification(.warning)
            }
        }
    }

    private func addToMeal(product: ScannedProduct) {
        let multiplier = portionQuantity
        let item = FoodItem(
            id: UUID(),
            name: product.name,
            brand: product.brand,
            servingSize: product.servingSize,
            servingQuantity: portionQuantity,
            calories: Int(Double(product.caloriesPerServing) * multiplier),
            protein: product.proteinPerServing * multiplier,
            carbs: product.carbsPerServing * multiplier,
            fat: product.fatPerServing * multiplier
        )
        HapticManager.notification(.success)
        onFoodScanned?(item)
        dismiss()
    }

    private func resetScanner() {
        scanState = .scanning
        scannedProduct = nil
        portionQuantity = 1.0
    }
}

// MARK: - ScannedProduct

struct ScannedProduct {
    let barcode: String
    let name: String
    let brand: String?
    let servingSize: String
    let caloriesPerServing: Int
    let proteinPerServing: Double
    let carbsPerServing: Double
    let fatPerServing: Double
    let imageName: String?
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
        // Start scanning if not already
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
}
