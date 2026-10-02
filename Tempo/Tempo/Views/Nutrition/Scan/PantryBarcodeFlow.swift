//
// PantryBarcodeScanView.swift
// Tempo
//
// Barcode → pantry. Reuses BarcodeScannerRepresentable + FoodCatalog (the
// same lookup BarcodeScannerView uses for meal logging) but hands off to
// PantryManualAddSheet for the actual confirm/edit/save — one save path,
// two entry points. Supports scanning several products in a row before
// handing off.
//

import SwiftData
import SwiftUI
import VisionKit

struct PantryBarcodeScanView: View {
    /// Called once, when the user taps Done, with every product scanned
    /// this session (possibly empty if they scan nothing and just leave).
    let onFinished: ([StagedPantryItem]) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State private var catalog: FoodCatalog?
    @State private var scanned: [StagedPantryItem] = []

    private enum ScanState: Equatable {
        case scanning
        case loading(String)
        case notFound(String)
        case failed(barcode: String, message: String)
        case unavailable
    }

    @State private var scanState: ScanState = .scanning

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary.ignoresSafeArea()
                switch scanState {
                case .scanning:
                    scannerContent
                case let .loading(code):
                    loadingContent(code)
                case let .notFound(code):
                    messageContent(
                        icon: "barcode.viewfinder",
                        title: "Not in the database",
                        message: "Barcode \(code) isn't recognized. Add it manually instead."
                    )
                case let .failed(_, message):
                    messageContent(icon: "wifi.exclamationmark", title: "Lookup failed", message: message)
                case .unavailable:
                    messageContent(
                        icon: "camera.fill",
                        title: "Camera scanning unavailable",
                        message: "Add items manually from the Pantry tab instead."
                    )
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(scanned.isEmpty ? "Done" : "Done (\(scanned.count))") {
                        onFinished(scanned)
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if catalog == nil {
                    catalog = FoodCatalog(services: services)
                }
                if !DataScannerViewController.isSupported || !DataScannerViewController.isAvailable {
                    scanState = .unavailable
                }
            }
        }
    }

    private var scannerContent: some View {
        ZStack {
            BarcodeScannerRepresentable { barcode in
                lookUp(barcode)
            }
            .ignoresSafeArea()

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: TempoRadius.xxxxl, style: .continuous)
                    .strokeBorder(Color.tempoSignal, lineWidth: 3)
                    .frame(width: 280, height: 180)
                Spacer()
                VStack(spacing: TempoSpacing.sm) {
                    Text("Point at a barcode")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoBone)
                    if !scanned.isEmpty {
                        Text("\(scanned.count) added — scan another or tap Done")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoBone.opacity(0.8))
                    }
                }
                .padding(.horizontal, TempoSpacing.xxl)
                .padding(.vertical, TempoSpacing.lg)
                .background(Color.tempoInk.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                .padding(.bottom, TempoSpacing.xxxxl)
            }
        }
    }

    private func loadingContent(_ code: String) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView().controlSize(.large)
            Text("Looking up \(code)…")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    private func messageContent(icon: String, title: String, message: String) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoAsh)
            Text(title)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.xxxxl)
            Button("Scan again") {
                scanState = .scanning
            }
            .buttonStyle(.tempoPrimary)
            Spacer()
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
                scanned.append(stagedItem(from: product))
                scanState = .scanning
            case let .notFound(code):
                HapticManager.warning()
                scanState = .notFound(code)
            case let .failed(message):
                HapticManager.error()
                scanState = .failed(barcode: code, message: message)
            }
        }
    }

    private func stagedItem(from product: FoodProduct) -> StagedPantryItem {
        StagedPantryItem(product: product)
    }
}
