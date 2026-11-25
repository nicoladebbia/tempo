@testable import Tempo
import XCTest

final class FirstTipsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "FirstTipsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testATipIsUnseenUntilMarked() {
        XCTAssertFalse(FirstTips.seen("train.logger", in: defaults))
        FirstTips.markSeen("train.logger", in: defaults)
        XCTAssertTrue(FirstTips.seen("train.logger", in: defaults))
        XCTAssertFalse(FirstTips.seen("fuel.scan", in: defaults))
    }

    func testResetBringsEveryTipBackAndLeavesOtherKeysAlone() {
        defaults.set("keep", forKey: "other.setting")
        FirstTips.markSeen("a", in: defaults)
        FirstTips.markSeen("b", in: defaults)
        FirstTips.resetAll(in: defaults)
        XCTAssertFalse(FirstTips.seen("a", in: defaults))
        XCTAssertFalse(FirstTips.seen("b", in: defaults))
        XCTAssertEqual(defaults.string(forKey: "other.setting"), "keep")
    }

    func testAnExplainerCarriesTheTappedValue() {
        let base = Explainer(id: "x", title: "Score", what: "a", how: "b", action: "c")
        XCTAssertNil(base.value)
        XCTAssertEqual(base.showing("82").value, "82")
        XCTAssertEqual(base.showing("82").id, "x")
    }
}
