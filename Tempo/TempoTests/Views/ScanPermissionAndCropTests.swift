//
// ScanPermissionAndCropTests.swift
// Tempo
//
// Back-from-Settings re-check rules and the label-crop rectangle math.
//

import AVFoundation
@testable import Tempo
import XCTest

final class ScanPermissionRecheckTests: XCTestCase {
    func testAuthorizedButScannerNotReadyIsRetried() {
        XCTAssertTrue(CameraPermission.shouldRecheck(status: .authorized, resolved: .unsupported, attempt: 0))
        XCTAssertTrue(CameraPermission.shouldRecheck(status: .authorized, resolved: .unsupported, attempt: 3))
    }

    func testRetriesAreBounded() {
        XCTAssertFalse(CameraPermission.shouldRecheck(status: .authorized, resolved: .unsupported, attempt: 4))
    }

    func testDeniedOrReadyIsNeverRetried() {
        XCTAssertFalse(CameraPermission.shouldRecheck(status: .denied, resolved: .denied, attempt: 0))
        XCTAssertFalse(CameraPermission.shouldRecheck(status: .authorized, resolved: .authorized, attempt: 0))
        // A real "no scanner camera" on a device that never granted access is final.
        XCTAssertFalse(CameraPermission.shouldRecheck(status: .notDetermined, resolved: .unsupported, attempt: 0))
    }

    func testDeniedThenGrantedResolvesToAuthorized() {
        XCTAssertEqual(CameraPermission.resolve(status: .denied, cameraSupported: true), .denied)
        XCTAssertEqual(CameraPermission.resolve(status: .authorized, cameraSupported: true), .authorized)
    }
}

final class LabelCropTests: XCTestCase {
    private let size = CGSize(width: 3000, height: 4000)

    func testNoDetectionFallsBackToCentredWindow() {
        let rect = LabelCrop.cropRect(normalizedBox: nil, imageSize: size)
        XCTAssertEqual(rect.midX, size.width / 2, accuracy: 0.5)
        XCTAssertEqual(rect.midY, size.height / 2, accuracy: 0.5)
        XCTAssertEqual(rect.width / rect.height, 4.0 / 3.0, accuracy: 0.01)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect))
    }

    func testTinyDetectionIsIgnored() {
        let tiny = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        XCTAssertEqual(
            LabelCrop.cropRect(normalizedBox: tiny, imageSize: size),
            LabelCrop.fallbackRect(imageSize: size)
        )
    }

    func testDetectionFlipsToTopLeftOriginAndStaysInside() {
        // Vision box in the bottom-left of the photo.
        let box = CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
        let rect = LabelCrop.cropRect(normalizedBox: box, imageSize: size)
        XCTAssertGreaterThan(rect.minY, size.height / 2 - 100) // lower half, padding allowed
        XCTAssertEqual(rect.minX, 0, accuracy: 0.5)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect))
    }

    func testLandscapePhotoFallbackFits() {
        let wide = CGSize(width: 4000, height: 1000)
        let rect = LabelCrop.fallbackRect(imageSize: wide)
        XCTAssertTrue(CGRect(origin: .zero, size: wide).contains(rect))
        XCTAssertEqual(rect.midX, 2000, accuracy: 0.5)
    }

    func testZeroSizeImageDoesNotCrash() {
        XCTAssertEqual(LabelCrop.cropRect(normalizedBox: nil, imageSize: .zero), .zero)
    }
}

final class ScanResumeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func record(_ kind: ScanContextKind, age: TimeInterval = 60) -> ScanResumeRecord? {
        kind.resumeKey.map { ScanResumeRecord(kind: $0, mode: "label", section: "Today", savedAt: now.addingTimeInterval(-age)) }
    }

    func testAuthorizedFreshRecordResumes() {
        for kind in [ScanContextKind.today, .foodCheck] {
            let rec = record(kind)
            XCTAssertEqual(ScanResume.decide(record: rec, cameraAuthorized: true, now: now), rec)
        }
    }

    func testStillDeniedDoesNothing() {
        XCTAssertNil(ScanResume.decide(record: record(.today), cameraAuthorized: false, now: now))
    }

    func testExpiredDoesNothing() {
        XCTAssertNil(ScanResume.decide(record: record(.today, age: ScanResume.maxAge + 1), cameraAuthorized: true, now: now))
        XCTAssertNotNil(ScanResume.decide(record: record(.today, age: ScanResume.maxAge), cameraAuthorized: true, now: now))
    }

    func testNoRecordOrUnknownKindDoesNothing() {
        XCTAssertNil(ScanResume.decide(record: nil, cameraAuthorized: true, now: now))
        let bad = ScanResumeRecord(kind: "pantryBarcode", mode: "barcode", section: "Kitchen", savedAt: now)
        XCTAssertNil(ScanResume.decide(record: bad, cameraAuthorized: true, now: now))
    }

    func testOnlyClosureFreeContextsAreResumable() {
        XCTAssertEqual(ScanContextKind.allCases.filter { $0.resumeKey != nil }.count, 2)
        XCTAssertNil(ScanContextKind.pantryBarcode.resumeKey)
        XCTAssertNil(ScanContextKind.supplements.resumeKey)
        XCTAssertNil(ScanContextKind.logMeal.resumeKey)
    }

    func testSaveLoadClearRoundTrip() {
        let defaults = UserDefaults(suiteName: "ScanResumeTests")!
        defaults.removePersistentDomain(forName: "ScanResumeTests")
        ScanResume.save(kind: .today, mode: .label, section: .today, now: now, defaults: defaults)
        XCTAssertEqual(ScanResume.load(defaults: defaults)?.scanMode, .label)
        ScanResume.save(kind: .pantryBarcode, mode: .barcode, section: .kitchen, now: now, defaults: defaults)
        XCTAssertEqual(ScanResume.load(defaults: defaults)?.kind, "today") // not resumable: ignored
        ScanResume.clear(defaults: defaults)
        XCTAssertNil(ScanResume.load(defaults: defaults))
    }
}
