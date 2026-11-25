//
// UniversalScanView.swift
// Tempo
//
// The one Scan screen. A mode chip switches between Barcode (live camera),
// Receipt (document camera), Label (nutrition-label photo → Add product) and
// Meal photo (photo analysis). The opener passes a `ScanContext` — which modes
// are offered, which one starts selected, and where the result goes — and
// every result ends in the opener's own confirm/review step: this screen
// never saves anything by itself.
//
//     UniversalScanView(context: .today())                          // Today / Scan button
//     UniversalScanView(context: .logMeal(onFood:, onMealPhoto:))   // Log, meal builder
//     UniversalScanView(context: .foodCheck)                        // Check a product
//
// Optional `initialMode` / `allowedModes` narrow the context's defaults (an
// initial mode the context doesn't allow falls back to the context's own).
//

import SwiftData
import SwiftUI

struct UniversalScanView: View {
    let context: ScanContext
    let allowedModes: [ScanMode]
    @State
    private var mode: ScanMode

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.scanResumeSection)
    private var resumeSection
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood

    @State
    private var catalog: FoodCatalog?
    /// Products carried across mode switches (see `ScanModeMemory`).
    @State
    private var memory = ScanModeMemory()
    @State
    private var permission = CameraPermission.current(needsLiveScanner: false)
    @State
    private var toast: ToastData?
    @State
    private var previousMode: ScanMode?
    /// Foods waiting in the Confirm Meal sheet, presented on top of the scanner.
    @State
    private var reviewRequest: MealReviewRequest?

    init(context: ScanContext, initialMode: ScanMode? = nil, allowedModes: [ScanMode]? = nil) {
        self.context = context
        let kindModes = context.kind.allowedModes
        let modes = allowedModes.map { requested in kindModes.filter(requested.contains) } ?? kindModes
        let resolved = modes.isEmpty ? kindModes : modes
        self.allowedModes = resolved
        let start = initialMode ?? context.kind.initialMode
        _mode = State(initialValue: resolved.contains(start) ? start : (resolved.first ?? context.kind.initialMode))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                content
                    .id(mode)
            }
            .kitchenPage()
            // A bar, not an inset: whatever scrolls under it (a product page)
            // fades out behind the modes instead of showing through them.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: Tide.s2) {
                    if allowedModes.count > 1 {
                        modeBar
                    }
                    if mode != .barcode, permission.isBlockedByUser {
                        permissionBanner
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s2)
                .background { barBacking }
            }
            .environment(\.scanResumeInfo, ScanResumeInfo(kind: context.kind, mode: mode, section: resumeSection))
            .firstTip("fuel.scan", "Pick Barcode, Label, Meal photo or Receipt at the top, then point the camera at it.")
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(context.kind.dismissTitle) { dismiss() }
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .accessibilityIdentifier("scanDismiss")
                }
            }
            .tempoToast($toast)
            .mealReview($reviewRequest) { dismiss() }
            .onAppear {
                if catalog == nil {
                    catalog = FoodCatalog(services: services)
                }
                permission = CameraPermission.current(needsLiveScanner: false)
            }
            .onChange(of: scenePhase) { _, phase in
                // Back from iOS Settings: the banner follows the real answer.
                if phase == .active {
                    permission = CameraPermission.current(needsLiveScanner: false)
                }
            }
            .onChange(of: mode) { old, _ in
                previousMode = old
                memory.modeChanged()
                permission = CameraPermission.current(needsLiveScanner: false)
            }
        }
        // The scanner is a cover: it draws its own field and its pushed pages
        // do too, whatever page presented it.
        .environment(\.tideInsidePage, false)
    }

    // MARK: - Mode bar

    /// Ink under the bar that fades out just below it, so a product page
    /// scrolling up never shows through the modes.
    private var barBacking: some View {
        LinearGradient(
            stops: [
                .init(color: Tide.ink.opacity(Tide.Kitchen.barBacking), location: 0),
                .init(color: Tide.ink.opacity(Tide.Kitchen.barBacking), location: 0.7),
                .init(color: Tide.ink.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .padding(.bottom, -Tide.s6)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var modeBar: some View {
        KitchenModeBar(
            options: allowedModes,
            selection: $mode,
            title: \.title,
            icon: \.icon,
            identifier: { "scanMode-\($0.rawValue)" }
        )
    }

    /// Photo modes still work from the library; only the camera is blocked.
    private var permissionBanner: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: "camera.fill")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.Kitchen.warn)
                .accessibilityHidden(true)
            Text("Camera is off for Tempo. You can still pick photos from your library.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open Settings") {
                ScanResume.save(kind: context.kind, mode: mode, section: resumeSection)
                CameraPermission.openSettings()
            }
            .font(Tide.bodyStrong)
            .foregroundStyle(mood.accent)
            .frame(minHeight: Tide.hit)
            .accessibilityIdentifier("scanOpenSettings")
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s2)
        .kitchenCameraPanel(radius: Tide.tileRadius)
        .accessibilityIdentifier("scanPermissionBanner")
    }

    // MARK: - Mode content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .barcode:
            barcodeContent
        case .receipt:
            receiptContent
        case .label:
            labelContent
        case .mealPhoto:
            mealPhotoContent
        }
    }

    @ViewBuilder
    private var barcodeContent: some View {
        switch context {
        case let .pantryBarcode(onFinished):
            PantryBarcodeFlow(onFinished: onFinished)
        case let .supplements(shelf, onSaved, lookupService):
            SupplementBarcodeFlow(shelf: shelf, onSaved: onSaved, injectedLookupService: lookupService)
        default:
            if case .logReview = context {
                FoodBarcodeFlow(
                    onFood: { reviewRequest = MealReviewRequest(foods: [$0]) },
                    dismissesAfterFood: false,
                    scannedProduct: $memory.scannedProduct
                )
            } else {
                FoodBarcodeFlow(onFood: context.foodCallback, scannedProduct: $memory.scannedProduct)
            }
        }
    }

    @ViewBuilder
    private var receiptContent: some View {
        switch context {
        case let .pantryReceipt(receiptService, pantryService, onIngested):
            ReceiptCaptureView(receiptService: receiptService, pantryService: pantryService, onIngested: onIngested)
        default:
            if let receiptService = services.receipts, let pantryService = services.pantry {
                ReceiptCaptureView(receiptService: receiptService, pantryService: pantryService)
            } else {
                unavailable("Receipts aren't ready yet. Open the Kitchen tab once, then scan again.")
            }
        }
    }

    @ViewBuilder
    private var labelContent: some View {
        if let catalog {
            switch memory.labelPage {
            case let .product(product):
                FoodProductView(product: product, mode: .check, catalog: catalog, recordsView: false)
                    .id(product.id)
            case let .scannedLabel(product):
                // Label of the product just scanned; photographing a better
                // label updates that same product.
                ScannedProductLabelView(
                    product: product,
                    catalog: catalog,
                    onUpdated: { memory.scannedProduct = $0 },
                    onScanAnother: {
                        memory.scanAnother()
                        mode = .barcode
                    }
                )
            case .capture:
                AddProductView(barcode: nil, catalog: catalog) { product in
                    memory.labelProduct = product
                }
            }
        }
    }

    private var mealPhotoContent: some View {
        PhotoAnalysisView(onCameraCancelled: leaveMealPhoto, dismissesOnConfirm: !reviewsInline) { items in
            switch context {
            case let .logMeal(_, onMealPhoto):
                onMealPhoto(items)
            case let .today(onMealPhoto?):
                onMealPhoto(items)
            case .today,
                 .logReview:
                // Confirm Meal opens right here, on top of the photo results.
                reviewRequest = MealReviewRequest(foods: items)
            default:
                break
            }
        }
    }

    /// Barcode "Add to meal" and meal photos are confirmed in the sheet over this screen.
    private var reviewsInline: Bool {
        switch context {
        case .logReview: true
        case let .today(onMealPhoto): onMealPhoto == nil
        default: false
        }
    }

    /// Cancelling the camera returns to the previous mode instead of closing the scanner.
    private func leaveMealPhoto() {
        let fallback = previousMode.flatMap { allowedModes.contains($0) && $0 != .mealPhoto ? $0 : nil }
            ?? allowedModes.first { $0 != .mealPhoto }
        if let fallback {
            mode = fallback
        } else {
            dismiss()
        }
    }

    private func unavailable(_ message: String) -> some View {
        KitchenStatePage(actions: allowedModes.contains(.barcode) && mode != .barcode ? [
            KitchenStateAction(title: "Back to barcode", systemImage: "barcode.viewfinder", role: .primary) {
                mode = .barcode
            },
        ] : []) {
            KitchenStateHero(
                systemImage: "camera.fill",
                tint: Tide.Kitchen.warn,
                title: "Scan unavailable",
                message: message
            )
        }
    }
}
