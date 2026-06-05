//
// ReceiptPhotoStoreTests.swift
// Tempo
//
// Covers the receipt-photo persistence that makes retry possible: save → load
// round-trip, delete removes the file, missing-photo load returns nil. These
// are the contract retryStructuring() relies on — if save/load drift, retry
// silently falls back to "re-capture the receipt".
//

@testable import Tempo
import Foundation
import XCTest

final class ReceiptPhotoStoreTests: XCTestCase {

    // Track ids we create so teardown never leaves files in App Support.
    private var createdIDs: [UUID] = []

    override func tearDown() {
        for id in createdIDs {
            ReceiptPhotoStore.delete(for: id)
        }
        createdIDs = []
        super.tearDown()
    }

    private func makeJPEG() -> Data {
        // Tiny but valid JPEG bytes via a 1x1 rendered image.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let img = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return img.jpegData(compressionQuality: 0.8)!
    }

    func test_saveThenLoad_roundTripsBytes() throws {
        let id = UUID()
        createdIDs.append(id)
        let jpeg = makeJPEG()

        let path = ReceiptPhotoStore.save(jpeg, for: id)
        XCTAssertNotNil(path, "save should return a path on success")

        let loaded = ReceiptPhotoStore.load(for: id)
        XCTAssertEqual(loaded, jpeg, "loaded bytes must equal saved bytes")
    }

    func test_load_missingPhoto_returnsNil() {
        // Never saved → retry must see nil and fall back to re-capture.
        let loaded = ReceiptPhotoStore.load(for: UUID())
        XCTAssertNil(loaded)
    }

    func test_delete_removesFile() throws {
        let id = UUID()
        let jpeg = makeJPEG()
        _ = ReceiptPhotoStore.save(jpeg, for: id)
        XCTAssertNotNil(ReceiptPhotoStore.load(for: id), "precondition: file exists")

        ReceiptPhotoStore.delete(for: id)
        XCTAssertNil(ReceiptPhotoStore.load(for: id), "delete must remove the file on disk")
    }

    func test_delete_missingPhoto_doesNotThrow() {
        // delete() is best-effort; deleting a non-existent photo is a no-op.
        ReceiptPhotoStore.delete(for: UUID())
    }
}
