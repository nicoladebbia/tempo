//
// PantryBarcodeFlow.swift
// Tempo
//
// Barcode mode for the Pantry. Same catalog lookup as the food flow (history
// first, then Open Food Facts) but each hit is staged, not saved: Done hands
// every product scanned this session to PantryManualAddSheet, which does the
// confirm/edit/save — one save path, two entry points.
//

import SwiftData
import SwiftUI

struct PantryBarcodeFlow: View {
    /// Called once, when the user taps Done, with every product scanned
    /// this session (possibly empty if they scan nothing and just leave).
    let onFinished: ([StagedPantryItem]) -> Void

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
    }

    @State private var scanState: ScanState = .scanning
    @Environment(\.tideMood) private var mood

    var body: some View {
        ZStack {
            TidePageBackground()
            switch scanState {
            case .scanning:
                ScanBarcodeSurface(
                    detail: scanned.isEmpty ? nil : String(localized: "\(scanned.count) added — scan another or tap Done")
                ) { barcode in
                    lookUp(barcode)
                }
            case let .loading(code):
                loadingContent(code)
            case let .notFound(code):
                messageContent(
                    icon: "barcode.viewfinder",
                    title: String(localized: "Not in the database"),
                    message: String(localized: "Barcode \(code) isn't recognized. Add it manually instead.")
                )
            case let .failed(_, message):
                messageContent(icon: "wifi.exclamationmark", title: String(localized: "Lookup failed"), message: message)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(scanned.isEmpty ? String(localized: "Done") : String(localized: "Done (\(scanned.count))")) {
                    onFinished(scanned)
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("scanDone")
            }
        }
        .onAppear {
            if catalog == nil {
                catalog = FoodCatalog(services: services)
            }
        }
    }

    private func loadingContent(_ code: String) -> some View {
        KitchenStatePage {
            KitchenStateHero(
                systemImage: "barcode.viewfinder",
                title: String(localized: "Looking up \(code)…"),
                working: true
            )
        }
    }

    private func messageContent(icon: String, title: String, message: String) -> some View {
        KitchenStatePage(actions: [
            KitchenStateAction(title: String(localized: "Scan again"), systemImage: "barcode.viewfinder", role: .primary) {
                scanState = .scanning
            },
        ]) {
            KitchenStateHero(systemImage: icon, tint: Tide.Kitchen.warn, title: title, message: message)
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
        if let cached = catalog.cachedProduct(barcode: code, in: modelContext) {
            HapticManager.success()
            catalog.recordView(cached, in: modelContext)
            scanned.append(StagedPantryItem(product: cached))
            scanState = .scanning
            Task { await catalog.refreshCached(barcode: code, in: modelContext) }
            return
        }
        scanState = .loading(code)
        HapticManager.mediumImpact()
        Task {
            switch await catalog.lookUp(barcode: code, in: modelContext) {
            case let .found(product):
                HapticManager.success()
                scanned.append(StagedPantryItem(product: product))
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
}
