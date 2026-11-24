//
// NutritionCoachMergeTests.swift
// Tempo
//
// The one Fuel coach page: the hydration tips quote the same water target as the
// Water card, the weigh-in push opens Fuel > Coach, and the page's session line
// reads the way the old Recovery screen did.
//

@testable import Tempo
import XCTest

final class NutritionCoachMergeTests: XCTestCase {
    func testHydrationTipQuotesTheWaterCardTargetNotANumberOfItsOwn() {
        for zone in ["red", "yellow", "green", "none"] {
            let tip = NutritionCoachView.hydrationTip(zone: zone, waterTargetMl: 3100)
            // Written the way the Water card writes it: "/ 3,100 ml".
            XCTAssertTrue(tip.contains("\(3100.formatted()) ml"), "\(zone): \(tip)")
            XCTAssertFalse(tip.contains("4L"), tip)
            XCTAssertFalse(tip.contains("3L"), tip)
        }
    }

    func testHydrationTipWithoutATargetStillReadsAsAWholeSentence() {
        let tip = NutritionCoachView.hydrationTip(zone: "red", waterTargetMl: nil)
        XCTAssertEqual(tip, "Hydration is critical. Add electrolytes.")
        XCTAssertFalse(NutritionCoachView.hydrationTip(zone: "yellow", waterTargetMl: nil).contains("  "))
    }

    func testSessionLineNamesTheSessionLengthAndHowLongAgo() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let end = now.addingTimeInterval(-20 * 60)
        let session = CoachSession(
            id: "s1", start: end.addingTimeInterval(-80 * 60), end: end, sportName: "soccer",
            strain: 14.8, kilojoules: 3500, averageHeartRate: 150, percentRecorded: 100
        )
        let line = RecoveryCoachSection.sessionLine(session, now: now)
        XCTAssertTrue(line.contains("80 min"), line)
        XCTAssertTrue(line.hasPrefix(session.label), line)
    }
}
