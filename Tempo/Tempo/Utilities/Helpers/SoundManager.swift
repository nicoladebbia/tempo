import AVFoundation
import UIKit

// MARK: - Sound Manager
// Per SOUND_AND_HAPTICS.md — Centralized sound playback.
// AVAudioSession category .ambient, mixes with other audio.
// Sounds are CAF files in Resources/Sounds/.
// All sound names follow: tempo_[module]_[action]

@MainActor
final class SoundManager {

    static let shared = SoundManager()

    private var players: [String: AVAudioPlayer] = [:]
    private var isEnabled: Bool = true

    private init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: - Sound Settings

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    // MARK: - Playback

    func play(_ sound: TempoSound, volume: Float? = nil) {
        guard isEnabled else { return }

        if let player = players[sound.rawValue], player.isPlaying {
            player.stop()
            player.currentTime = 0
            player.volume = volume ?? sound.defaultVolume
            player.play()
            return
        }

        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf")
                ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
            // Sound file not yet added — silently skip
            return
        }

        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = volume ?? sound.defaultVolume
        player.prepareToPlay()
        player.play()
        players[sound.rawValue] = player
    }

    /// Play for timer completions — uses .playback to cut through music
    func playImportant(_ sound: TempoSound) {
        guard isEnabled else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        play(sound, volume: 1.0)
        // Restore ambient after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            try? session.setCategory(.ambient, options: [.mixWithOthers])
        }
    }
}

// MARK: - Sound Catalog
// Per SOUND_AND_HAPTICS.md Section 2

enum TempoSound: String {
    // Workout
    case workoutSetComplete = "tempo_workout_set_complete"
    case workoutExerciseComplete = "tempo_workout_exercise_complete"
    case workoutStart = "tempo_workout_start"
    case workoutComplete = "tempo_workout_complete"
    case workoutRestTick = "tempo_workout_rest_tick"
    case workoutRestDone = "tempo_workout_rest_done"
    case workoutPRachieved = "tempo_workout_pr_achieved"
    case workoutWeightAdjust = "tempo_workout_weight_adjust"

    // Timer
    case timerStart = "tempo_timer_start"
    case timerTick = "tempo_timer_tick"
    case timerComplete = "tempo_timer_complete"
    case timerBreakStart = "tempo_timer_break_start"

    // Arena
    case arenaXPGain = "tempo_arena_xp_gain"
    case arenaLevelUp = "tempo_arena_level_up"
    case arenaAchievement = "tempo_arena_achievement"
    case arenaStreakFire = "tempo_arena_streak_fire"
    case arenaChallengeWon = "tempo_arena_challenge_won"

    // System
    case systemTabSwitch = "tempo_system_tab_switch"
    case systemNNComplete = "tempo_system_nn_complete"
    case systemLeisureUnlock = "tempo_system_leisure_unlock"

    var defaultVolume: Float {
        switch self {
        case .workoutRestTick: return 0.5
        case .workoutSetComplete: return 0.7
        case .workoutExerciseComplete, .workoutRestDone: return 0.8
        case .workoutStart: return 0.9
        case .workoutComplete, .workoutPRachieved: return 1.0
        case .timerTick: return 0.4
        case .timerComplete: return 0.9
        case .arenaXPGain: return 0.6
        case .arenaLevelUp, .arenaChallengeWon: return 1.0
        case .systemTabSwitch: return 0.3
        default: return 0.7
        }
    }
}
