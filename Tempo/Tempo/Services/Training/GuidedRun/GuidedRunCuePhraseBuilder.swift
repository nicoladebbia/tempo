//
// GuidedRunCuePhraseBuilder.swift
// Tempo
//
// Guided run mode — pure text for every `GuidedRunCue`, in EN or IT. Split
// out of `GuidedRunCueService` (which owns the AVSpeechSynthesizer/audio
// session side effects) so phrase selection is unit-testable with no
// AVFoundation dependency (GuidedRunCuePhraseBuilderTests).
//

import Foundation

enum GuidedRunCuePhraseBuilder {
    static func phrase(for cue: GuidedRunCue, isItalian: Bool) -> String {
        switch cue {
        case let .countdown(value):
            String(value)
        case .go:
            isItalian ? "Via" : "Go"
        case .restStart:
            isItalian ? "Recupero" : "Rest"
        case .tenSecondsLeft:
            isItalian ? "Dieci secondi" : "Ten seconds"
        case .halfway:
            isItalian ? "A metà" : "Halfway"
        case .done:
            isItalian ? "Fatto. Sessione completata." : "Done. Session complete."
        case let .repStart(index, of, capSeconds, isLast):
            repStartPhrase(index: index, of: of, capSeconds: capSeconds, isLast: isLast, isItalian: isItalian)
        case let .repResult(elapsedSeconds, capSeconds):
            repResultPhrase(elapsedSeconds: elapsedSeconds, capSeconds: capSeconds, isItalian: isItalian)
        }
    }

    /// Under/over the cap — the haptic the service plays alongside this cue
    /// depends on the same test, so it's exposed rather than buried in the
    /// phrase text.
    static func isOverCap(_ cue: GuidedRunCue) -> Bool {
        guard case let .repResult(elapsedSeconds, capSeconds) = cue, let capSeconds else {
            return false
        }
        return elapsedSeconds > capSeconds
    }

    private static func repStartPhrase(index: Int, of: Int, capSeconds: Double?, isLast: Bool, isItalian: Bool) -> String {
        let cap = capSeconds.map { formatSeconds($0) }
        if isItalian {
            let lead = isLast ? "Ultima rep" : "Rep \(index + 1) di \(of)"
            return cap.map { "\(lead), cap \($0)" } ?? lead
        }
        let lead = isLast ? "Last rep" : "Rep \(index + 1) of \(of)"
        return cap.map { "\(lead) — cap \($0)" } ?? lead
    }

    private static func repResultPhrase(elapsedSeconds: Double, capSeconds: Double?, isItalian: Bool) -> String {
        let time = formatSeconds(elapsedSeconds)
        guard let capSeconds else {
            return time
        }
        let overCap = elapsedSeconds > capSeconds
        if isItalian {
            return overCap
                ? "Sopra il cap — \(time). Spingi la prossima."
                : "Sotto il cap — \(time). Bene."
        }
        return overCap
            ? "Over — \(time). Push the next one."
            : "Under the cap — \(time). Nice."
    }

    /// "58 seconds" under a minute, "1:05" once it crosses one.
    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 {
            return "\(total) seconds"
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
