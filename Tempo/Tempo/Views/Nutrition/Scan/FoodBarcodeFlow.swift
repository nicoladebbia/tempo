//
// FoodBarcodeFlow.swift
// Tempo
//
// Barcode mode for the food contexts (Log, meal builder, food search, Food
// check, Today). A scan is looked up in FoodCatalog — a product seen before
// opens instantly from history while a background refresh updates it — then
// shows the product page. With `onFood` the page says "Add to meal" and hands
// the item back; without it it's scan-to-check and nothing is logged. Unknown
// barcodes can be added with two photos. Nothing here saves until the user
// taps a button on the product page.
//

import SwiftData
import SwiftUI

struct FoodBarcodeFlow: View {
    var onFood: ((FoodItem) -> Void)?
    /// The product on screen, owned by the scanner so it survives switching
    /// to another mode (Label shows its nutrition table) and back. Cleared
    /// only by "Scan another".
    @Binding
    var scannedProduct: FoodProduct?

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var scanState: ScanState
    @State
    private var showAddProduct = false
    @State
    private var showSearch = false
    @State
    private var catalog: FoodCatalog?
    @State
    private var network = NetworkStatus()

    /// False when the opener shows the next screen over this one and closes the flow itself.
    private let dismissesAfterFood: Bool

    init(
        onFood: ((FoodItem) -> Void)? = nil,
        dismissesAfterFood: Bool = true,
        scannedProduct: Binding<FoodProduct?> = .constant(nil)
    ) {
        self.onFood = onFood
        self.dismissesAfterFood = dismissesAfterFood
        _scannedProduct = scannedProduct
        _scanState = State(initialValue: scannedProduct.wrappedValue.map(ScanState.found) ?? .scanning)
    }

    enum ScanState: Equatable {
        case scanning
        case loading(String)
        case found(FoodProduct)
        case notFound(String)
        case failed(barcode: String, message: String)
    }

    var body: some View {
        ZStack {
            TidePageBackground()
            switch scanState {
            case .scanning:
                ScanBarcodeSurface(
                    detail: "Instant score: nutrition, additives, what it means for you today.",
                    fallbackActions: [ScanFallbackAction(title: "Search by name") { showSearch = true }],
                    isOffline: network.isOffline,
                    onSearchOffline: { showSearch = true }
                ) { barcode in
                    lookUp(barcode)
                }
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
            }
        }
        .onChange(of: scanState) { _, state in
            // Mirror the product up so other modes can use it; a new scan clears it.
            if case let .found(product) = state {
                scannedProduct = product
            } else if case .scanning = state {
                scannedProduct = nil
            }
        }
        .toolbar {
            if case .found = scanState {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        scanState = .scanning
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
        .sheet(isPresented: $showSearch) {
            FoodSearchView(onFoodSelected: onFood.map { handler in
                { item in
                    if dismissesAfterFood {
                        handler(item)
                        dismiss()
                    } else {
                        // The opener shows its next screen over the scanner:
                        // let the search sheet finish closing first.
                        showSearch = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            handler(item)
                        }
                    }
                }
            })
        }
        .onAppear {
            if catalog == nil {
                catalog = FoodCatalog(services: services)
            }
        }
        .task {
            await network.monitor()
        }
    }

    private var productMode: FoodProductView.Mode {
        guard let onFood else {
            return .check
        }
        return .log { item in
            onFood(item)
            if dismissesAfterFood {
                dismiss()
            }
        }
    }

    private var currentBarcode: String? {
        switch scanState {
        case let .notFound(code),
             let .loading(code),
             let .failed(code, _): code
        case let .found(product): product.barcode
        default: nil
        }
    }

    // MARK: - Loading

    /// The product page's own shape, shimmering: the picture, then the score.
    private var loadingContent: some View {
        VStack(spacing: Tide.s4) {
            VStack(spacing: Tide.s4) {
                RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                    .fill(Tide.fill)
                    .frame(height: Tide.Kitchen.heroPicture)
                VStack(alignment: .leading, spacing: Tide.s2) {
                    RoundedRectangle(cornerRadius: Tide.controlRadius)
                        .fill(Tide.fill)
                        .frame(width: Tide.Kitchen.heroPicture, height: Tide.s5)
                    RoundedRectangle(cornerRadius: Tide.controlRadius)
                        .fill(Tide.fill)
                        .frame(width: Tide.Kitchen.suggestion, height: Tide.s4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                    .fill(Tide.fill)
                    .frame(height: Tide.Kitchen.verdictDial + Tide.s10)
            }
            .shimmer()
            Text("Looking up product…")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Looking up product")
    }

    // MARK: - Not found

    private func notFoundContent(_ barcode: String) -> some View {
        VStack(spacing: Tide.s4) {
            Spacer()
            VStack(spacing: Tide.s4) {
                KitchenHeroDisc(systemImage: "barcode.viewfinder")
                VStack(spacing: Tide.s2) {
                    Text("Not in the database yet")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Barcode \(barcode). Add it once with two photos — every scan after that is instant.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: Tide.s3) {
                    Button("Add this product") {
                        showAddProduct = true
                    }
                    .buttonStyle(.tidePrimary)
                    .accessibilityIdentifier("addMissingProduct")

                    Button("Search by name") {
                        showSearch = true
                    }
                    .buttonStyle(.tideGlass)

                    Button("Scan again") {
                        scanState = .scanning
                    }
                    .buttonStyle(.tideGlass)
                }
                .padding(.top, Tide.s2)
            }
            .frame(maxWidth: .infinity)
            .tideCard(padding: Tide.s6)
            .frame(maxWidth: Tide.stateWidth)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tide.edge)
    }

    // MARK: - Failed

    private func failedContent(barcode: String, message: String) -> some View {
        VStack {
            Spacer()
            KitchenFailure(
                title: "Couldn't look it up",
                message: message,
                retry: { lookUp(barcode) },
                secondaryTitle: "Scan again",
                secondary: { scanState = .scanning }
            )
            Spacer()
        }
        .padding(.horizontal, Tide.edge)
    }

    // MARK: - Actions

    private func lookUp(_ barcode: String) {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty, let catalog else {
            return
        }
        if case .loading = scanState {
            return
        }
        // Seen before: open it now, refresh quietly. No spinner, no network wait.
        if let cached = catalog.cachedProduct(barcode: code, in: modelContext) {
            HapticManager.success()
            scanState = .found(cached)
            catalog.recordView(cached, in: modelContext)
            Task { await catalog.refreshCached(barcode: code, in: modelContext) }
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
}
