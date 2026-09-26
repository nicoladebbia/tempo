//
// GuidedRunCueService.swift
// Tempo
//
// Guided run mode — turns a `GuidedRunCue` from the session engine into
// haptics + a spoken/played cue. Reuses the app's existing cue
// infrastructure rather than inventing a parallel one: `HapticManager` for
// impact/notification feedback, `CueAudioPlayer` (AVSpeechSynthesizer
// fallback, no bundled clips for these closed-vocabulary phrases yet — they
// speak via Apple's voice like any `.dynamic` cue) for the spoken side.
// Respects a mute toggle so the athlete can run silent.
//

import Foundation

@MainActor
final class GuidedRunCueService {
    var isMuted = false

    func handle(_ cue: GuidedRunCue) {
        switch cue {
        case let .countdown(value):
            HapticManager.impact(.light)
            speak(String(value))
        case .go:
            HapticManager.impact(.heavy)
            speak("Go")
        case .restStart:
            HapticManager.notification(.warning)
            speak("Rest")
        case .tenSecondsLeft:
            HapticManager.impact(.light)
            speak("Ten seconds")
        case .halfway:
            HapticManager.impact(.medium)
            speak("Halfway")
        case .done:
            HapticManager.notification(.success)
            speak("Done. Session complete.")
        }
    }

    private func speak(_ phrase: String) {
        guard !isMuted else {
            return
        }
        CueAudioPlayer.shared.play(.dynamic(phrase))
    }
}
