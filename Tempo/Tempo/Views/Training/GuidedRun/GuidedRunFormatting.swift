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

    static func distance(meters: Double, useMiles: Bool) -> String {
        if useMiles {
            let miles = meters / 1609.344
            return String(format: "%.2f mi", miles)
        }
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    /// "5:12/km" / "8:23/mi" — nil when there isn't a meaningful pace yet.
    static func pace(secondsPerKm: Double?, useMiles: Bool) -> String? {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0 else {
            return nil
        }
        let secondsPerUnit = useMiles ? secondsPerKm * 1.609344 : secondsPerKm
        let total = Int(secondsPerUnit.rounded())
        return String(format: "%d:%02d/%@", total / 60, total % 60, useMiles ? "mi" : "km")
    }

    /// Short description of a work step, used for the block list, the
    /// "up next" preview on the rest screen, and the summary.
    static func workDescription(_ kind: GuidedRunWorkKind) -> String {
        switch kind {
        case let .timedRep(rep):
            var parts = ["Rep \(rep.index + 1)/\(rep.of)"]
            if let distanceLabel = rep.distanceLabel {
                parts.append(distanceLabel)
            }
            if let capSeconds = rep.capSeconds {
                parts.append("cap \(repTime(capSeconds))")
            }
            return parts.joined(separator: " · ")
        case let .round(index, of):
            return "Round \(index + 1)/\(of)"
        case let .continuousDuration(targetSeconds):
            return "\(Int((targetSeconds / 60).rounded())) min continuous"
        case let .continuousDistance(_, targetLabel):
            return "\(targetLabel) continuous"
        case let .freeform(text):
            return text
        }
    }
}
