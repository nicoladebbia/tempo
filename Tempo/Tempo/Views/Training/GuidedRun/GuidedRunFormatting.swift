//
// GuidedRunFormatting.swift
// Tempo
//
// Guided run mode — shared display text/number formatting for the live
// coach screens and the summary, kept in one place so the countdown/work/
// rest/summary views (and their tests) agree on the same strings.
//

import Foundation

enum GuidedRunFormatting {
    /// "0:07", "1:05" — stopwatch/countdown style, always m:ss even under a
    /// minute (a run screen reads better with a stable digit count).
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "58\"", "1:05" — matches ConditioningLogSheet's rep-time style.
    static func repTime(_ seconds: TimeInterval) -> String {
        seconds >= 60
            ? String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
            : "\(Int(seconds.rounded()))\""
    }

    /// Miles vs km for every run surface. There's no separate distance
    /// setting: the weight unit tracks metric/imperial (lbs → miles), with a
    /// locale fallback before a settings row exists.
    static func useMiles(weightUnit: WeightUnit?, locale: Locale = .current) -> Bool {
        if let weightUnit {
            return weightUnit == .lbs
        }
        return locale.measurementSystem != .metric
    }

    /// "12.4 km" / "7.7 mi" — one-decimal running total for stat headers.
    static func totalDistance(meters: Double, useMiles: Bool) -> String {
        useMiles
            ? String(localized: "\((meters / 1609.344).tempoDecimal(1)) mi")
            : String(localized: "\((meters / 1000).tempoDecimal(1)) km")
    }

    static func distance(meters: Double, useMiles: Bool) -> String {
        if useMiles {
            let miles = meters / 1609.344
            return String(localized: "\(miles.tempoDecimal(2)) mi")
        }
        if meters >= 1000 {
            return String(localized: "\((meters / 1000).tempoDecimal(2)) km")
        }
        return String(localized: "\(Int(meters.rounded())) m")
    }

    /// "5:12/km" / "8:23/mi" — nil when there isn't a meaningful pace yet.
    static func pace(secondsPerKm: Double?, useMiles: Bool) -> String? {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0 else {
            return nil
        }
        let secondsPerUnit = useMiles ? secondsPerKm * 1.609344 : secondsPerKm
        let total = Int(secondsPerUnit.rounded())
        let clock = String(format: "%d:%02d", total / 60, total % 60)
        return useMiles ? String(localized: "\(clock)/mi") : String(localized: "\(clock)/km")
    }

    /// Short description of a work step, used for the block list, the
    /// "up next" preview on the rest screen, and the summary.
    static func workDescription(_ kind: GuidedRunWorkKind) -> String {
        switch kind {
        case let .timedRep(rep):
            var parts = [String(localized: "Rep \(rep.index + 1)/\(rep.of)")]
            if let distanceLabel = rep.distanceLabel {
                parts.append(distanceLabel)
            }
            if let capSeconds = rep.capSeconds {
                parts.append(String(localized: "cap \(repTime(capSeconds))"))
            }
            return parts.joined(separator: " · ")
        case let .round(index, of):
            return String(localized: "Round \(index + 1)/\(of)")
        case let .continuousDuration(targetSeconds):
            return String(localized: "\(Int((targetSeconds / 60).rounded())) min continuous")
        case let .continuousDistance(_, targetLabel):
            return String(localized: "\(targetLabel) continuous")
        case let .freeform(text):
            return text
        }
    }
}
