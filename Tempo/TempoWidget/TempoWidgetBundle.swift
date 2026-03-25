import SwiftUI
import WidgetKit

// MARK: - Tempo Widget Bundle
// Per XCODE_PROJECT_STRUCTURE.md Section 10.5 — @main WidgetBundle.

@main
struct TempoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TempoWidget()
        TempoLockScreenWidget()
    }
}
