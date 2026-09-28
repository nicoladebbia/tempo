//
// GuidedRunActivityAttributes.swift
// Tempo
//
// Guided run mode — the Live Activity attributes type. `ContentState` is
// `GuidedRunActivitySnapshot` (Foundation-only, shared 3 ways — see its
// header) so this file itself only needs `import ActivityKit`, which is why
// it's shared with TempoWidget but NOT TempoWatch (ActivityKit doesn't exist
// on watchOS). Mirrors WorkoutActivityAttributes/FocusTimerActivityAttributes.
//

import ActivityKit
import Foundation

struct GuidedRunActivityAttributes: ActivityAttributes {
    typealias ContentState = GuidedRunActivitySnapshot

    /// The day's heading ("PUSH — Conditioning"), shown once in the widget
    /// chrome rather than repeated in every ContentState.
    var runTitle: String
}
