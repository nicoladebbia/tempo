//
// CueAudioPlayer.swift
// Tempo
//
// Plays short workout audio cues. Prefers a pre-rendered premium voice clip
// (bundled .mp3, generated once via ElevenLabs) for the CLOSED cue vocabulary —
// countdown phrases + the fixed warm-up move names. Falls back to the on-device
// AVSpeechSynthesizer for anything without a clip (e.g. user-added custom
// exercise names, which are an open set). This makes the fallback boundary
// deterministic: fixed cues = premium clip, dynamic names = Apple voice.
//
// No runtime API cost and fully offline: the clips are static assets bundled in
// the app, not live TTS calls.
//

import AVFoundation

// MARK: - Cue

/// The closed set of pre-renderable cues. Each maps to a bundled clip filename;
/// if the clip is absent the player speaks `spoken` via AVSpeechSynthesizer.
enum WarmupCue {
    case tenSeconds
    case three
    case two
    case one
    case go
    /// A fixed warm-up move announcement (move names are authored in
    /// WarmupRoutine — a closed set we control, so they can be pre-rendered).
    case warmupMove(slug: String, spoken: String)
    /// Dynamic free text (e.g. a working-set exercise name from the open
    /// library). Never has a clip — always spoken.
    case dynamic(String)

    /// Bundled clip resource name (without extension), or nil if always-spoken.
    var clipName: String? {
        switch self {
        case .tenSeconds: "cue_ten_seconds"
        case .three: "cue_three"
        case .two: "cue_two"
        case .one: "cue_one"
        case .go: "cue_go"
        case let .warmupMove(slug, _): "cue_move_\(slug)"
        case .dynamic: nil
        }
    }

    /// What the Apple voice says when no clip is available.
    var spoken: String {
        switch self {
        case .tenSeconds: "Get ready — ten seconds"
        case .three: "Three"
        case .two: "Two"
        case .one: "One"
        case .go: "Go"
        case let .warmupMove(_, spoken): spoken
        case let .dynamic(text): text
        }
    }
}

// MARK: - CueAudioPlayer

@MainActor
final class CueAudioPlayer {
    static let shared = CueAudioPlayer()

    private var players: [String: AVAudioPlayer] = [:]
    private let synth = AVSpeechSynthesizer()

    /// Best available offline English voice for the fallback path.
    private lazy var fallbackVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    private init() {}

    /// Preload the players for a set of cues so playback at fire-time has no
    /// disk latency (call at rest-start, not on the countdown tick).
    func preload(_ cues: [WarmupCue]) {
        for cue in cues {
            guard let name = cue.clipName, players[name] == nil,
                  let url = Self.clipURL(name)
            else {
                continue
            }
            players[name] = try? AVAudioPlayer(contentsOf: url)
            players[name]?.prepareToPlay()
        }
    }

    /// Play a cue: bundled premium clip if present, else Apple speech.
    func play(_ cue: WarmupCue) {
        if let name = cue.clipName, let player = preparedPlayer(name) {
            player.currentTime = 0
            player.play()
            return
        }
        speak(cue.spoken)
    }

    /// True if a premium clip exists for this cue (lets callers tune lead-time:
    /// clips start in ms, speech needs ~2s spin-up).
    func hasClip(_ cue: WarmupCue) -> Bool {
        guard let name = cue.clipName else {
            return false
        }
        return preparedPlayer(name) != nil
    }

    // MARK: - Private

    private func preparedPlayer(_ name: String) -> AVAudioPlayer? {
        if let p = players[name] {
            return p
        }
        guard let url = Self.clipURL(name), let p = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }
        p.prepareToPlay()
        players[name] = p
        return p
    }

    private func speak(_ phrase: String) {
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.volume = 1.0
        utterance.voice = fallbackVoice
        synth.speak(utterance)
    }

    private static func clipURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "CueAudio")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3")
    }
}
