//
// ScanContext.swift
// Tempo
//
// What UniversalScanView can scan (ScanMode) and who opened it (ScanContext).
// The context decides which modes the chip shows, which one starts selected,
// and where each result goes. The scanner itself never writes anything: every
// route ends in the caller's existing confirm/review step.
//

import Foundation

// MARK: - ScanMode

enum ScanMode: String, CaseIterable, Identifiable {
    case barcode
    case receipt
    case label
    case mealPhoto

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .barcode: "Barcode"
        case .receipt: "Receipt"
        case .label: "Label"
        case .mealPhoto: "Meal photo"
        }
    }

    var icon: String {
        switch self {
        case .barcode: "barcode.viewfinder"
        case .receipt: "receipt"
        case .label: "text.viewfinder"
        case .mealPhoto: "fork.knife"
        }
    }
}

// MARK: - ScanRoute

/// Where a scan result lands.
enum ScanRoute: Equatable {
    /// FoodProductView in Check mode (score, then Log / Pantry / List).
    case foodProductPage
    /// A `FoodItem` handed back to the caller (Log / meal builder / search).
    case foodItemCallback
    /// Products staged for the pantry sheet.
    case pantryStaging
    /// Supplement shelf: add or restock.
    case supplementShelf
    /// Receipt review, then pantry ingest.
    case receiptReview
    /// AddProductView (label photo), then the product page.
    case addProduct
    /// PhotoAnalysisView confirm, then the caller's log review.
    case mealPhotoReview
}

// MARK: - ScanContextKind

enum ScanContextKind: CaseIterable {
    case today
    case logMeal
    case foodSearch
    case foodCheck
    case pantryBarcode
    case pantryReceipt
    case supplements

    var allowedModes: [ScanMode] {
        switch self {
        case .today: [.barcode, .receipt, .label, .mealPhoto]
        case .logMeal: [.barcode, .mealPhoto]
        case .foodSearch,
             .pantryBarcode,
             .supplements: [.barcode]
        case .foodCheck: [.barcode, .label]
        case .pantryReceipt: [.receipt]
        }
    }

    var initialMode: ScanMode {
        switch self {
        case .pantryReceipt: .receipt
        default: .barcode
        }
    }

    /// Leading toolbar button: nothing is pending in the check hubs.
    var dismissTitle: String {
        switch self {
        case .today,
             .foodCheck: "Done"
        default: "Cancel"
        }
    }

    /// Nil when the context doesn't take that mode.
    func route(for mode: ScanMode) -> ScanRoute? {
        guard allowedModes.contains(mode) else {
            return nil
        }
        switch (self, mode) {
        case (.pantryBarcode, .barcode): return .pantryStaging
        case (.supplements, .barcode): return .supplementShelf
        case (.logMeal, .barcode),
             (.foodSearch, .barcode): return .foodItemCallback
        case (_, .barcode): return .foodProductPage
        case (_, .receipt): return .receiptReview
        case (_, .label): return .addProduct
        case (_, .mealPhoto): return .mealPhotoReview
        }
    }
}

// MARK: - ScanContext

/// Who opened the scanner, and what to call with the result.
///
/// ```swift
/// // Lane C / Today: one entry, every mode, results routed in-app.
/// .fullScreenCover(isPresented: $showScan) { UniversalScanView(context: .today()) }
/// ```
/// `.today()` routes barcode to the product page (Log / Pantry / List), receipt to
/// receipt review, label to Add product and meal photo to a logged meal (via
/// `onMealPhoto` when given, otherwise logged with the time-of-day meal type).
enum ScanContext {
    case today(onMealPhoto: (([FoodItem]) -> Void)? = nil)
    /// Log tab and meal builder: barcode and meal photo hand foods back.
    case logMeal(onFood: (FoodItem) -> Void, onMealPhoto: ([FoodItem]) -> Void)
    /// Food search toolbar; nil callback = scan-to-check.
    case foodSearch(onFood: ((FoodItem) -> Void)?)
    case foodCheck
    case pantryBarcode(onFinished: ([StagedPantryItem]) -> Void)
    case pantryReceipt(receiptService: any ReceiptServiceProtocol, pantryService: any PantryServiceProtocol, onIngested: (() -> Void)?)
    case supplements(shelf: [Supplement], onSaved: () -> Void, lookupService: (any SupplementLookupServicing)? = nil)

    var kind: ScanContextKind {
        switch self {
        case .today: .today
        case .logMeal: .logMeal
        case .foodSearch: .foodSearch
        case .foodCheck: .foodCheck
        case .pantryBarcode: .pantryBarcode
        case .pantryReceipt: .pantryReceipt
        case .supplements: .supplements
        }
    }

    /// The caller's per-food callback, when it has one.
    var foodCallback: ((FoodItem) -> Void)? {
        switch self {
        case let .logMeal(onFood, _): onFood
        case let .foodSearch(onFood): onFood
        default: nil
        }
    }
}
