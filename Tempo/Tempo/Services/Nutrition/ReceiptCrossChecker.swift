//
// ReceiptCrossChecker.swift
// Tempo
//
// Deterministic math cross-check run AFTER structuring (Haiku or manual
// edits) to catch the case where the model compiles clean but the numbers
// don't add up — a receipt that "compiles" but shows the wrong total is
// exactly the kind of bug that's invisible until you check the arithmetic.
//
// Two checks, run independently so a banner can name which one failed:
//   1. sum(line items) + fees - discounts  vs  subtotal
//   2. subtotal + tax                       vs  total
// A mismatch over `toleranceCents` (default $0.50 — OCR/rounding noise on a
// 25-item receipt easily hits a few cents, so this is deliberately not
// zero-tolerance) surfaces a review banner naming the likely culprit.
//

import Foundation

// MARK: - ReceiptCrossCheckResult

struct ReceiptCrossCheckResult: Sendable {
    let isConsistent: Bool
    /// User-facing banner text, e.g. "Check these lines — items add up to
    /// $145.10 but the receipt subtotal is $142.32 ($2.78 too high)."
    /// nil when consistent or when there isn't enough data to check.
    let bannerMessage: String?
    let subtotalDelta: Double?
    let totalDelta: Double?
    /// Index (into the items array passed in) of the single line item whose
    /// magnitude most plausibly explains the subtotal mismatch — a cheap
    /// "closest single culprit" heuristic, not a guarantee. nil when the
    /// mismatch isn't well-explained by any one line, or there's no mismatch.
    let likelyCulpritIndex: Int?
}

// MARK: - ReceiptCrossChecker

enum ReceiptCrossChecker {
    static func check(
        itemTotals: [Double],
        subtotal: Double?,
        tax: Double?,
        total: Double?,
        toleranceCents: Double = 0.50
    ) -> ReceiptCrossCheckResult {
        let itemSum = itemTotals.reduce(0, +)

        var subtotalDelta: Double?
        var totalDelta: Double?
        var messages: [String] = []
        var culprit: Int?

        if let subtotal {
            let delta = (itemSum - subtotal).rounded(toPlaces: 2)
            subtotalDelta = delta
            if abs(delta) > toleranceCents {
                let direction = delta > 0 ? "too high" : "too low"
                messages.append(
                    "Items add up to \(currency(itemSum)) but the receipt subtotal is \(currency(subtotal)) (\(currency(abs(delta))) \(direction))."
                )
                culprit = closestCulprit(itemTotals: itemTotals, delta: delta)
            }
        }

        if let subtotal, let tax, let total {
            let expectedTotal = subtotal + tax
            let delta = (expectedTotal - total).rounded(toPlaces: 2)
            totalDelta = delta
            if abs(delta) > toleranceCents {
                messages.append(
                    "Subtotal + tax is \(currency(expectedTotal)) but the printed total is \(currency(total))."
                )
            }
        } else if let total {
            // No subtotal/tax breakdown available — fall back to a direct
            // items-vs-total check so we still catch gross mismatches.
            let delta = (itemSum - total).rounded(toPlaces: 2)
            if abs(delta) > max(toleranceCents, 1.0) { // items-vs-TOTAL naturally excludes tax, wider tolerance
                totalDelta = delta
                messages.append(
                    "Items add up to \(currency(itemSum)) but the printed total is \(currency(total)) — this receipt may include tax or fees not itemized."
                )
            }
        }

        let isConsistent = messages.isEmpty
        return ReceiptCrossCheckResult(
            isConsistent: isConsistent,
            bannerMessage: isConsistent ? nil : ("Check these lines — " + messages.joined(separator: " ")),
            subtotalDelta: subtotalDelta,
            totalDelta: totalDelta,
            likelyCulpritIndex: culprit
        )
    }

    /// If exactly one item's price is close to the mismatch amount, it's the
    /// most likely single culprit (e.g. a duplicated line, or a price the
    /// OCR/model misread) — surfaced as a hint, not a guarantee.
    private static func closestCulprit(itemTotals: [Double], delta: Double) -> Int? {
        let target = abs(delta)
        guard target > 0.01 else {
            return nil
        }
        var bestIndex: Int?
        var bestDiff = Double.greatestFiniteMagnitude
        for (index, price) in itemTotals.enumerated() {
            let diff = abs(price - target)
            if diff < bestDiff, diff < 0.05 {
                bestDiff = diff
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
