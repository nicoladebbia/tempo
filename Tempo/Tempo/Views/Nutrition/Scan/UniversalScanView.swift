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
                Color.tempoBgPrimary.ignoresSafeArea()
                content
                    .id(mode)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if allowedModes.count > 1 {
                        modeChips
                    }
                    if mode != .barcode, permission.isBlockedByUser {
                        permissionBanner
                    }
                }
            }
            .environment(\.scanResumeInfo, ScanResumeInfo(kind: context.kind, mode: mode, section: resumeSection))
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(context.kind.dismissTitle) { dismiss() }
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextSecondary)
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
    }

    // MARK: - Mode chips

    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TempoSpacing.sm) {
                ForEach(allowedModes) { candidate in
                    let selected = candidate == mode
                    Button {
                        HapticManager.lightImpact()
                        mode = candidate
                    } label: {
                        Label(candidate.title, systemImage: candidate.icon)
                            .font(.tempoCallout)
                            .padding(.horizontal, TempoSpacing.md)
                            .padding(.vertical, TempoSpacing.sm)
                            .foregroundStyle(selected ? Color.tempoInk : Color.tempoTextPrimary)
                            .background(selected ? Color.tempoSignal : Color.tempoSurfaceCard)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("scanMode-\(candidate.rawValue)")
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.sm)
        }
        .background(Color.tempoBgPrimary)
    }

    /// Photo modes still work from the library; only the camera is blocked.
    private var permissionBanner: some View {
        HStack(spacing: TempoSpacing.md) {
            Text("Camera is off for Tempo. You can still pick photos from your library.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer(minLength: 0)
            Button("Open Settings") {
                ScanResume.save(kind: context.kind, mode: mode, section: resumeSection)
                CameraPermission.openSettings()
            }
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoSignal)
                .accessibilityIdentifier("scanOpenSettings")
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
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
        EmptyStateView(icon: "camera.fill", title: "Scan unavailable", message: message)
    }
}
