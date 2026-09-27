//
// GuidedRunCueService.swift
// Tempo
//
// Guided run mode — turns a `GuidedRunCue` from the session engine into
// haptics + a spoken cue. Owns its OWN `AVSpeechSynthesizer` + audio session
// (rather than routing through the shared `CueAudioPlayer`, which speaks a
// fixed English-only vocabulary for other features) so guided-run cues can
// follow the app's own locale (IT/EN) and pick the best available
// enhanced/premium voice for whichever language that is, independently.
//
// Ducks (not stops) any music the athlete is playing — `.playback` +
// `.spokenAudio` + `.duckOthers`, same category shape as
// `TrainingViewModel.activateRestAudioSession()` — active only for the
// lifetime of a live session (`startSession()`/`endSession()`). Respects a
// mute toggle so the athlete can run silent; muting is the ONLY thing that
// suppresses a cue — `.playback` intentionally still plays through the
// hardware silent switch, matching how every other Tempo workout cue works.
//

import AVFoundation
import Foundation

@MainActor
final class GuidedRunCueService {
    var isMuted = false

    private let synth = AVSpeechSynthesizer()

    /// Best available enhanced/premium voice for the app's current language,
    /// falling back gracefully: premium → enhanced → default system voice
    /// for that language → a hardcoded en-US voice so speech never silently
    /// fails to have ANY voice.
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let languageCode = Self.preferredLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode) }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: languageCode == "it" ? "it-IT" : "en-US")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// "it" or "en" — follows the app's own locale (Settings → General →
    /// Language & Region), not a separate in-app picker.
    private static func preferredLanguageCode() -> String {
        Locale.current.language.languageCode?.identifier == "it" ? "it" : "en"
    }

    private var isItalian: Bool {
        Self.preferredLanguageCode() == "it"
    }

    // MARK: - Session audio lifecycle

    /// Activate the ducking audio session — call once when a guided run
    /// starts (before any cue fires).
    func startSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }

    /// Release the audio session so the athlete's music returns to full
    /// volume — call when the session ends (finished, discarded, or the
    /// screen is dismissed).
    func endSession() {
        synth.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Cue handling

    func handle(_ cue: GuidedRunCue) {
        haptic(for: cue)
        speak(GuidedRunCuePhraseBuilder.phrase(for: cue, isItalian: isItalian))
    }

    private func haptic(for cue: GuidedRunCue) {
        switch cue {
        case .countdown:
            HapticManager.impact(.light)
        case .go:
            HapticManager.impact(.heavy)
        case .restStart:
            HapticManager.notification(.warning)
        case .tenSecondsLeft:
            HapticManager.impact(.light)
        case .halfway:
            HapticManager.impact(.medium)
        case .done:
            HapticManager.notification(.success)
        case .repStart:
            HapticManager.impact(.medium)
        case .repResult:
            HapticManager.notification(GuidedRunCuePhraseBuilder.isOverCap(cue) ? .warning : .success)
        }
    }

    private func speak(_ phrase: String) {
        guard !isMuted else {
            return
        }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.volume = 1.0
        utterance.voice = voice
        synth.speak(utterance)
    }
}
