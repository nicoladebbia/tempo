//
// ProgressPhotoStoreTests.swift
// Tempo
//
// Progress photos live as files on the phone: names carry the date, listing is
// newest first, only our own files can be listed or deleted.
//

@testable import Tempo
import UIKit
import XCTest

final class ProgressPhotoStoreTests: XCTestCase {
    private var folder: URL!
    private var store: ProgressPhotoStore!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "progress-photos-\(UUID().uuidString)")
        store = ProgressPhotoStore(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func date(_ day: Int, hour: Int = 8) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: 15, second: 30))!
    }

    private let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])

    func testAFileNameCarriesTheDateItWasTakenOn() {
        let name = ProgressPhotoStore.fileName(for: date(24), token: "ABCD1234")
        XCTAssertEqual(name, "20261124-081530-ABCD1234.jpg")
        XCTAssertEqual(ProgressPhotoStore.date(fromFileName: name), date(24))
    }

    func testFilesThatAreNotOursHaveNoDate() {
        XCTAssertNil(ProgressPhotoStore.date(fromFileName: "IMG_0001.jpg"))
        XCTAssertNil(ProgressPhotoStore.date(fromFileName: "20261124-081530-ABCD1234.png"))
        XCTAssertNil(ProgressPhotoStore.date(fromFileName: "2026-11-24-0815.jpg"))
        XCTAssertNil(ProgressPhotoStore.date(fromFileName: ".DS_Store"))
    }

    func testAnEmptyOrMissingFolderListsNothing() {
        XCTAssertTrue(store.photos().isEmpty)
    }

    func testAddedPhotosListNewestFirst() throws {
        try store.add(jpegData: bytes, date: date(10))
        try store.add(jpegData: bytes, date: date(24))
        try store.add(jpegData: bytes, date: date(17))
        XCTAssertEqual(store.photos().map(\.date), [date(24), date(17), date(10)])
    }

    func testTwoPhotosInTheSameSecondDoNotOverwriteEachOther() throws {
        try store.add(jpegData: bytes, date: date(10))
        try store.add(jpegData: bytes, date: date(10))
        XCTAssertEqual(store.photos().count, 2)
    }

    func testTheStoredBytesAreWhatWasAdded() throws {
        let photo = try store.add(jpegData: bytes, date: date(10))
        XCTAssertEqual(try Data(contentsOf: photo.url), bytes)
    }

    func testDeleteRemovesOnlyThatPhoto() throws {
        let keep = try store.add(jpegData: bytes, date: date(10))
        let gone = try store.add(jpegData: bytes, date: date(24))
        try store.delete(gone)
        XCTAssertEqual(store.photos().map(\.id), [keep.id])
    }

    func testOtherFilesInTheFolderAreIgnoredAndNeverDeleted() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stray = folder.appending(path: "notes.txt")
        try Data("keep me".utf8).write(to: stray)
        XCTAssertTrue(store.photos().isEmpty)

        // A forged photo that points outside the folder is not deleted.
        let forged = ProgressPhoto(id: "20261124-081530-ABCD1234.jpg", date: date(24), url: stray)
        try store.delete(forged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stray.path))
    }

    func testBigPhotosAreScaledDownAndSmallOnesAreNot() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let bigData = try XCTUnwrap(ProgressPhotoStore.jpegData(from: big))
        let bigSize = try XCTUnwrap(UIImage(data: bigData)).size
        XCTAssertEqual(max(bigSize.width, bigSize.height), ProgressPhotoStore.maxStoredDimension)

        let small = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        }
        let smallSize = try XCTUnwrap(UIImage(data: XCTUnwrap(ProgressPhotoStore.jpegData(from: small)))).size
        XCTAssertEqual(smallSize, CGSize(width: 600, height: 800))
    }

    func testAThumbnailIsSmallerThanThePhoto() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
        }
        let photo = try store.add(jpegData: XCTUnwrap(ProgressPhotoStore.jpegData(from: image)), date: date(10))
        let thumb = try XCTUnwrap(store.thumbnail(for: photo, maxPixel: 200))
        XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height) * thumb.scale, 200)
    }

    func testAPictureIsScaledAndSavedOffTheMainThread() async throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let fromCamera = try await store.add(picture: big)
        let fromLibrary = try await store.add(pictureData: XCTUnwrap(big.pngData()))
        XCTAssertEqual(store.photos().count, 2)
        for photo in [fromCamera, fromLibrary] {
            let size = try XCTUnwrap(store.image(for: photo)).size
            XCTAssertEqual(max(size.width, size.height), ProgressPhotoStore.maxStoredDimension)
        }
    }

    func testBytesThatAreNotAPictureAreRefusedAndNothingIsSaved() async {
        do {
            _ = try await store.add(pictureData: Data([0x00, 0x01, 0x02]))
            XCTFail("expected the bytes to be refused")
        } catch {
            XCTAssertEqual(error as? ProgressPhotoStore.AddError, .unreadable)
        }
        XCTAssertTrue(store.photos().isEmpty)
    }

    func testTwoPhotosOfOneDayAreToldApartByTime() {
        let morning = ProgressPhoto(id: "a", date: date(10, hour: 8), url: folder)
        let evening = ProgressPhoto(id: "b", date: date(10, hour: 19), url: folder)
        let other = ProgressPhoto(id: "c", date: date(17), url: folder)
        let all = [morning, evening, other]

        XCTAssertNotEqual(morning.menuLabel(among: all), evening.menuLabel(among: all))
        XCTAssertTrue(morning.menuLabel(among: all).contains(":") || morning.menuLabel(among: all).contains("."))
        XCTAssertEqual(other.menuLabel(among: all), other.date.formatted(date: .abbreviated, time: .omitted))
    }

    func testThePhotoFolderIsKeptOutOfBackups() throws {
        XCTAssertFalse(store.isExcludedFromBackup)
        try store.add(jpegData: bytes, date: date(10))
        XCTAssertTrue(store.isExcludedFromBackup)
    }
}
