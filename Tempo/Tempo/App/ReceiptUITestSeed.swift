//
// ReceiptUITestSeed.swift
// Tempo
//
// DEBUG-only QA fixture: with `--uitesting-receipt-sample` (plus the
// nutrition-plan flag that hooks it) the app gets one scanned receipt waiting
// for review — a mix of confident, shaky, frozen and non-food lines, one with
// a matched product photo — so the review screen can be checked in the
// simulator, which has no camera.
//

import Foundation
import SwiftData

#if DEBUG
    enum ReceiptUITestSeed {
        static let launchArgument = "--uitesting-receipt-sample"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains(launchArgument) else {
                return
            }
            let existing = (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
            guard existing.isEmpty else {
                return
            }
            let receipt = Receipt(
                store: "Publix",
                purchaseDate: Date(),
                totalAmount: 61.37,
                ocrStatus: .awaitingReview
            )
            receipt.savingsAmount = 6.20
            receipt.storeChain = "publix"
            context.insert(receipt)
            func add(_ raw: String, _ canonical: String, _ name: String, _ qty: Double, _ unit: ReceiptLineUnit, _ price: Double,
                     confidence: Double = 0.96, nonFood: Bool = false, fee: Bool = false, size: (Double, String)? = nil,
                     barcode: String? = nil, image: String? = nil, match: Double? = nil, brand: String? = nil, at offset: Double)
            {
                let line = ReceiptLineItem(
                    receipt: receipt, rawText: raw, canonicalFoodName: canonical, displayName: name,
                    quantity: qty, unit: unit, totalPrice: price, confidence: confidence,
                    isNonFood: nonFood, isFee: fee, barcode: barcode, brand: brand,
                    sizeValue: size?.0, sizeUnit: size?.1, imageURL: image, matchConfidence: match
                )
                line.createdAt = Date(timeIntervalSince1970: offset)
                context.insert(line)
            }
            add("GV WHL MILK GAL", "milk", "Whole milk", 1, .each, 3.89, size: (1, "gal"), at: 1)
            add("CHKN BRST 2.1LB", "chicken breast", "Chicken breast", 2.1, .pounds, 9.45, at: 2)
            add("BANANAS 1.5LB", "banana", "Bananas", 1.5, .pounds, 0.89, at: 3)
            add("NUTELLA 13OZ", "hazelnut spread", "Hazelnut spread", 1, .each, 4.49, size: (13, "oz"),
                barcode: "3017620422003", image: "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.879.400.jpg",
                match: 0.88, brand: "Nutella", at: 4)
            add("FRZ BROC FLRTS", "frozen broccoli", "Frozen broccoli", 2, .each, 4.58, at: 5)
            add("BRWN RICE 2LB", "brown rice", "Brown rice", 1, .each, 3.29, at: 6)
            add("OLV OIL EV 500ML", "olive oil", "Olive oil", 1, .bottle, 8.99, at: 7)
            add("PRT PWDR CHOC", "protein powder", "Protein powder", 1, .each, 0, confidence: 0.55, at: 8)
            add("K1 SPRKLNG WTR", "sparkling water", "K", 1, .each, 5.99, confidence: 0.42, at: 9)
            add("EGGS LRG 18CT", "eggs", "Eggs", 1, .each, 5.79, at: 10)
            add("BAG FEE", "bag fee", "Bag fee", 1, .each, 0.10, fee: true, at: 11)
            add("DAWN DISH SOAP", "dish soap", "Dish soap", 1, .each, 3.99, nonFood: true, at: 12)
            add("PAPER TOWELS 6PK", "paper towels", "Paper towels", 1, .each, 9.99, nonFood: true, at: 13)
            try? context.save()
        }
    }
#endif
