//
// RecoveryCoachMath.swift
// Tempo
//
// Pure helpers for the Recovery Coach screens: which session to show, how much
// fluid to report, the quick-answer buttons, and the plain-English text of a
// sweat range. No sweat math here: that is all server-side.
//

import Foundation

// MARK: - Quick answer

/// The four buttons on the weigh-in notification. `rawValue` is the action id.
enum CoachQuickAnswerAction: String, CaseIterable, Sendable {
    case nothing = "COACH_DRANK_NOTHING"
    case halfBottle = "COACH_DRANK_HALF"
    case oneBottle = "COACH_DRANK_ONE"
    case twoBottles = "COACH_DRANK_TWO"

    var bottles: Double {
        switch self {
        case .nothing: 0
        case .halfBottle: 0.5
        case .oneBottle: 1
        case .twoBottles: 2
        }
    }

    var title: String {
        switch self {
        case .nothing: String(localized: "Nothing")
        case .halfBottle: String(localized: "Half a bottle")
        case .oneBottle: String(localized: "One bottle")
        case .twoBottles: String(localized: "Two bottles")
        }
    }
}

// MARK: - Fluids

struct CoachFluidBreakdown: Equatable, Sendable {
    /// Tempo water taps inside the session window, ml.
    let loggedMl: Int
    let quickAnswerLiters: Double?
    let editedLiters: Double?

    /// nil = nothing is known, so the server says "at least".
    var liters: Double? {
        if let editedLiters { return editedLiters }
        if quickAnswerLiters == nil, loggedMl == 0 { return nil }
        return (quickAnswerLiters ?? 0) + Double(loggedMl) / 1000
    }
}

// MARK: - Session choice

enum RecoverySessionPicker {
    static let maxAge: TimeInterval = 48 * 3600

    /// The latest finished session of the last 48 h that is not "ready" yet;
    /// when every one has a result, the latest one. nil = nothing to show.
    static func focus(
        sessions: [CoachSession], now: Date, isReady: (String) -> Bool
    ) -> CoachSession? {
        let recent = sessions
            .filter { $0.end <= now && now.timeIntervalSince($0.end) <= maxAge }
            .sorted { $0.end > $1.end }
        return recent.first { !isReady($0.id) } ?? recent.first
    }
}

// MARK: - Wording

enum RecoveryCoachFormat {
    static func liters(_ value: Double) -> String {
        "\(value.tempoDecimal(1)) L"
    }

    /// Under a litre in mL, otherwise litres with up to 2 decimals: "375 mL", "1.5 L", "1.25 L".
    static func fluid(_ liters: Double) -> String {
        if liters < 1 { return String(localized: "\(Int((liters * 1000).rounded())) mL") }
        var text = String(format: "%.2f", liters)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        // `text` only decides how many decimals are left; the number itself follows the user's format.
        let digits = text.split(separator: ".").dropFirst().first?.count ?? 0
        return "\(liters.tempoDecimal(digits)) L"
    }

    /// "1.5 to 1.6 L" (or "1.5 L" when both round the same).
    static func litersRange(low: Double, high: Double) -> String {
        let a = low.tempoDecimal(1), b = high.tempoDecimal(1)
        return a == b ? "\(a) L" : String(localized: "\(a) to \(b) L")
    }

    /// Round to 10 mg: no false precision on a range this wide.
    static func sodium(_ mg: Double) -> String {
        String(localized: "\(Int((mg / 10).rounded()) * 10) mg")
    }

    static func sodiumRange(low: Double, high: Double) -> String {
        String(localized: "\(Int((low / 10).rounded()) * 10) to \(Int((high / 10).rounded()) * 10) mg")
    }

    /// "+/- 11%" from the server's margin; never claims 5%.
    static func margin(_ percent: Double) -> String {
        "+/- \(Int(percent.rounded()))%"
    }

    /// Coarse location for the weather lookup: 0.1 degree, about 11 km.
    static func coarse(_ degrees: Double) -> Double {
        (degrees * 10).rounded() / 10
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
