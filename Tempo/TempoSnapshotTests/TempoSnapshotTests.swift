import XCTest
import SnapshotTesting
import SwiftUI
@testable import Tempo

// MARK: - Snapshot Test Base
// Per BUILD_PLAN Step 19.4, TESTING_STRATEGY.md Section 6.
// Uses swift-snapshot-testing to capture reference images.
//
// First run: set `isRecording = true` in setUp() to generate reference images.
// Subsequent runs: set `isRecording = false` to assert against references.

@MainActor
class TempoSnapshotTestCase: XCTestCase {

    /// Standard test device config: iPhone 15 Pro (393x852 logical points).
    let snapshotConfig = ViewImageConfig.iPhoneX

    override func setUp() {
        super.setUp()
        // Toggle to true to (re-)record reference images.
        // isRecording = true
    }

    /// Snapshot a SwiftUI view wrapped in a hosting controller with dark mode.
    func assertDarkSnapshot<V: View>(
        of view: V,
        named name: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let controller = UIHostingController(
            rootView: view
                .preferredColorScheme(.dark)
                .frame(width: 393)
        )
        controller.overrideUserInterfaceStyle = .dark

        assertSnapshot(
            of: controller,
            as: .image(on: snapshotConfig),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }

    /// Snapshot a component view at a fixed size.
    func assertComponentSnapshot<V: View>(
        of view: V,
        size: CGSize,
        named name: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let controller = UIHostingController(
            rootView: view
                .preferredColorScheme(.dark)
                .frame(width: size.width, height: size.height)
        )
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: size)

        assertSnapshot(
            of: controller,
            as: .image(size: size),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }
}
