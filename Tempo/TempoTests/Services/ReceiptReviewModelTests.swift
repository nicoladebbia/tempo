//
// ReceiptReviewModelTests.swift
// Tempo
//
// Grouping/sorting, needs-a-look rules, include rules and the
// photo-only-when-confident rule for the receipt review screen.
//

import Foundation
@testable import Tempo
import UIKit
import XCTest

@MainActor
final class ReceiptReviewModelTests: XCTestCase {
    private func line(
        _ name: String,
        canonical: String? = nil,
        price: Double = 3,
        qty: Double = 1,
        confidence: Double = 0.95,
        nonFood: Bool = false,
        fee: Bool = false,
        barcode: String? = nil,
        imageURL: String? = nil,
        match: Double? = nil
    ) -> ReceiptLineItem {
        ReceiptLineItem(
            rawText: name.uppercased(),
            canonicalFoodName: canonical ?? name.lowercased(),
            displayName: name,
            quantity: qty,
            unit: .each,
            totalPrice: price,
            confidence: confidence,
            isNonFood: nonFood,
            isFee: fee,
            barcode: barcode,
            imageURL: imageURL,
            matchConfidence: match
        )
    }

    private func model(_ lines: [ReceiptLineItem]) -> ReceiptReviewModel {
        let receipt = Receipt(store: "Publix", purchaseDate: Date(), totalAmount: 20)
        for (index, item) in lines.enumerated() {
            item.createdAt = Date(timeIntervalSince1970: Double(index))
        }
        receipt.lineItems = lines
        return ReceiptReviewModel(receipt: receipt)
    }

    // MARK: Needs a look

    func testNeedsLookRules() {
        let ok = line("Bananas")
        let lowConfidence = line("Mystery", confidence: 0.5)
        let noPrice = line("Apples", price: 0)
        let noQty = line("Pears", qty: 0)
        let shortName = line("X")
        let weakMatch = line("Yogurt", barcode: "123", match: 0.3)
        let notFood = line("Soap", confidence: 0.2, nonFood: true)
        let m = model([ok, lowConfidence, noPrice, noQty, shortName, weakMatch, notFood])
        XCTAssertFalse(m.needsLook(ok))
        XCTAssertTrue(m.needsLook(lowConfidence))
        XCTAssertTrue(m.needsLook(noPrice))
        XCTAssertTrue(m.needsLook(noQty))
        XCTAssertTrue(m.needsLook(shortName))
        XCTAssertTrue(m.needsLook(weakMatch))
        XCTAssertFalse(m.needsLook(notFood), "non-food never needs a look")
        XCTAssertEqual(m.needsLookCount, 5)
    }

    func testReviewingARowClearsNeedsLook() {
        let shaky = line("Mystery", confidence: 0.5)
        let m = model([shaky])
        m.update(shaky) { $0.reviewed = true }
        XCTAssertFalse(m.needsLook(shaky))
    }

    // MARK: Grouping & sorting

    func testSectionOrderAndMembership() {
        let milk = line("Milk", canonical: "milk")
        let peas = line("Frozen peas", canonical: "frozen peas")
        let rice = line("Rice", canonical: "rice")
        let shaky = line("Zzz", confidence: 0.4)
        let soap = line("Soap", nonFood: true)
        let bag = line("Bag fee", fee: true)
        let m = model([rice, soap, milk, shaky, peas, bag])
        let sections = m.sections()
        XCTAssertEqual(sections.map(\.section), [.needsLook, .fridge, .freezer, .pantry, .notFood])
        XCTAssertEqual(sections[0].lines.map(\.displayName), ["Zzz"])
        XCTAssertEqual(sections[1].lines.map(\.displayName), ["Milk"])
        XCTAssertEqual(sections[2].lines.map(\.displayName), ["Frozen peas"])
        XCTAssertEqual(sections[3].lines.map(\.displayName), ["Rice"])
        XCTAssertEqual(Set(sections[4].lines.map(\.displayName)), ["Soap", "Bag fee"])
    }

    func testNeedsLookSortsLeastCertainFirstOthersAlphabetical() {
        let a = line("Alpha", confidence: 0.6)
        let b = line("Beta", confidence: 0.3)
        let m = model([a, b])
        XCTAssertEqual(m.sections()[0].lines.map(\.displayName), ["Beta", "Alpha"])
        let rice = line("rice", canonical: "rice")
        let oats = line("Oats", canonical: "oats")
        let m2 = model([rice, oats])
        XCTAssertEqual(m2.sections()[0].lines.map(\.displayName), ["Oats", "rice"])
    }

    func testStorageOverrideMovesLineBetweenSections() {
        let rice = line("Rice", canonical: "rice")
        let m = model([rice])
        m.update(rice) { $0.storage = .freezer }
        XCTAssertEqual(m.sections().map(\.section), [.freezer])
    }

    // MARK: Include / remove / commit

    func testNonFoodExcludedByDefaultFoodIncluded() {
        let soap = line("Soap", nonFood: true)
        let rice = line("Rice")
        let m = model([soap, rice])
        XCTAssertFalse(m.isIncluded(soap))
        XCTAssertTrue(m.isIncluded(rice))
        XCTAssertEqual(m.includedCount, 1)
        m.update(soap) { $0.included = true }
        XCTAssertEqual(m.includedCount, 2)
    }

    func testRemoveAndUndo() {
        let rice = line("Rice")
        let oats = line("Oats")
        let m = model([rice, oats])
        m.remove(rice)
        XCTAssertEqual(m.includedCount, 1)
        XCTAssertEqual(m.sections().flatMap(\.lines).count, 1)
        m.undoRemove()
        XCTAssertEqual(m.includedCount, 2)
        XCTAssertNil(m.lastRemoved)
    }

    func testCommitConfirmsOnlyIncludedAndCarriesOverrides() {
        let rice = line("Rice")
        let soap = line("Soap", nonFood: true)
        let oats = line("Oats")
        let m = model([rice, soap, oats])
        let expiry = Date(timeIntervalSinceNow: 86400)
        m.update(rice) { $0.storage = .fridge; $0.useBy = expiry }
        m.remove(oats)
        let overrides = m.commit()
        XCTAssertTrue(rice.userConfirmed)
        XCTAssertFalse(soap.userConfirmed)
        XCTAssertFalse(oats.userConfirmed)
        XCTAssertEqual(overrides.count, 1)
        XCTAssertEqual(overrides[rice.id]?.storage, .fridge)
        XCTAssertEqual(overrides[rice.id]?.useBy, expiry)
    }

    // MARK: Product photo rule

    func testPhotoOnlyWhenConfidentMatchWithImage() {
        let url = "https://images.openfoodfacts.org/x.jpg"
        XCTAssertNotNil(ReceiptProductPhoto.url(imageURL: url, barcode: "123", matchConfidence: 0.8, userPicked: false))
        XCTAssertNil(ReceiptProductPhoto.url(imageURL: url, barcode: "123", matchConfidence: 0.4, userPicked: false), "weak match: no photo")
        XCTAssertNil(ReceiptProductPhoto.url(imageURL: url, barcode: "123", matchConfidence: nil, userPicked: false))
        XCTAssertNil(ReceiptProductPhoto.url(imageURL: url, barcode: nil, matchConfidence: 0.9, userPicked: false), "no product = guess")
        XCTAssertNil(ReceiptProductPhoto.url(imageURL: nil, barcode: "123", matchConfidence: 0.9, userPicked: false))
        XCTAssertNil(ReceiptProductPhoto.url(imageURL: "javascript:x", barcode: "123", matchConfidence: 0.9, userPicked: false))
        XCTAssertNotNil(ReceiptProductPhoto.url(imageURL: url, barcode: "123", matchConfidence: 0.2, userPicked: true), "user's own pick always counts")
    }

    func testModelPhotoURLUsesRule() {
        let matched = line("Yogurt", barcode: "999", imageURL: "https://x.test/y.jpg", match: 0.9)
        let guessed = line("Milk", imageURL: "https://x.test/m.jpg")
        let m = model([matched, guessed])
        XCTAssertNotNil(m.photoURL(for: matched))
        XCTAssertNil(m.photoURL(for: guessed))
    }

    func testCategoryIconsExist() {
        for name in ["banana", "chicken", "salmon", "milk", "rice", "frozen peas", "olive oil", "tea bags"] {
            let icon = ReceiptProductPhoto.categoryIcon(forCanonicalName: name, isNonFood: false)
            XCTAssertNotNil(UIImage(systemName: icon), "\(icon) missing for \(name)")
        }
        XCTAssertNotNil(UIImage(systemName: ReceiptProductPhoto.categoryIcon(forCanonicalName: "soap", isNonFood: true)))
    }
}
