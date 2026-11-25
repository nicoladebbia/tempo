//
// TideMood.swift
// Tempo
//
// The day's state colours the whole app: the background field, the accent,
// and the one word that sums the day up.
//

import SwiftUI

struct TideMood: Equatable {
    enum Level: String, CaseIterable {
        /// 67 and up.
        case onPace
        /// 34 to 66.
        case behind
        /// 33 and under: the clear "bad day" state.
        case offTrack
        /// No score yet (new user, nothing synced).
        case unknown
    }

    let level: Level

    init(level: Level) {
        self.level = level
    }

    /// `score` is the 0-100 day score; nil when there is none yet.
    init(score: Int?) {
        guard let score else {
            level = .unknown
            return
        }
        switch score {
        case 67...: level = .onPace
        case 34 ..< 67: level = .behind
        default: level = .offTrack
        }
    }

    static let neutral = TideMood(level: .unknown)

    var word: String {
        switch level {
        case .onPace: String(localized: "On pace")
        case .behind: String(localized: "Behind")
        case .offTrack: String(localized: "Off track")
        case .unknown: String(localized: "No score yet")
        }
    }

    /// The colour of "now" and "do this".
    var accent: Color {
        switch level {
        case .onPace: Color(red: 0.42, green: 0.96, blue: 0.80)
        case .behind: Color(red: 1.00, green: 0.80, blue: 0.40)
        case .offTrack: Color(red: 1.00, green: 0.50, blue: 0.52)
        case .unknown: Color(red: 0.66, green: 0.78, blue: 1.00)
        }
    }

    var glowA: Color {
        switch level {
        case .onPace: Color(red: 0.04, green: 0.50, blue: 0.47)
        case .behind: Color(red: 0.62, green: 0.38, blue: 0.08)
        case .offTrack: Color(red: 0.62, green: 0.10, blue: 0.22)
        case .unknown: Color(red: 0.14, green: 0.26, blue: 0.52)
        }
    }

    var glowB: Color {
        switch level {
        case .onPace: Color(red: 0.16, green: 0.24, blue: 0.72)
        case .behind: Color(red: 0.36, green: 0.18, blue: 0.62)
        case .offTrack: Color(red: 0.26, green: 0.10, blue: 0.44)
        case .unknown: Color(red: 0.20, green: 0.16, blue: 0.46)
        }
    }

    var ember: Color {
        switch level {
        case .onPace: Color(red: 0.95, green: 0.62, blue: 0.30)
        case .behind: Color(red: 0.95, green: 0.42, blue: 0.30)
        case .offTrack: Color(red: 0.90, green: 0.36, blue: 0.20)
        case .unknown: Color(red: 0.42, green: 0.40, blue: 0.70)
        }
    }
}

extension EnvironmentValues {
    /// The current mood. Set once at the app shell; read by every Tide component.
    @Entry var tideMood: TideMood = .neutral
}
