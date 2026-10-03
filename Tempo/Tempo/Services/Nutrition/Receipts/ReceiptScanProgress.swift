//
// ReceiptScanProgress.swift
// Tempo
//
// Live progress of one receipt scan, so the processing screen can say what
// is really happening and show the store / total as soon as the on-device
// pre-parse has them. The view binds one of these to the scan Task via a
// TaskLocal; LiveReceiptService reports into it. No protocol change.
//

import Foundation
import Observation

@MainActor
@Observable
final class ReceiptScanProgress {
    enum Stage: Int, CaseIterable, Comparable, Sendable {
        case reading
        case findingItems
        case matchingProducts
        case checkingPrices

        static func < (lhs: Stage, rhs: Stage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var title: String {
            switch self {
            case .reading: "Reading receipt"
            case .findingItems: "Finding items"
            case .matchingProducts: "Matching your products"
            case .checkingPrices: "Checking prices"
            }
        }

        var detail: String {
            switch self {
            case .reading: "On-device text recognition"
            case .findingItems: "Splitting the text into line items"
            case .matchingProducts: "Looks up exact products as you review"
            case .checkingPrices: "Compares with what you paid before"
            }
        }
    }

    private(set) var stage: Stage = .reading
    private(set) var storeName: String?
    private(set) var totalAmount: Double?
    private(set) var itemCandidateCount: Int?
    /// Set once the whole scan call returned.
    private(set) var isFinished = false

    func advance(to newStage: Stage) {
        if newStage > stage {
            stage = newStage
        }
    }

    func parsed(store: String?, total: Double?, itemCount: Int?) {
        if let store, !store.isEmpty {
            storeName = store
        }
        if let total, total > 0 {
            totalAmount = total
        }
        if let itemCount, itemCount > 0 {
            itemCandidateCount = itemCount
        }
    }

    func finish() {
        isFinished = true
        stage = .checkingPrices
    }

    /// Stage state for the checklist: done / active / upcoming. Matching and
    /// price checks continue on the review screen after the scan returns, so
    /// they only turn "done" when the scan has finished handing over.
    func state(of candidate: Stage) -> StageState {
        if isFinished {
            return .done
        }
        if candidate < stage {
            return .done
        }
        return candidate == stage ? .active : .upcoming
    }

    enum StageState: Sendable {
        case done, active, upcoming
    }

    @TaskLocal
    static var current: ReceiptScanProgress?
}
