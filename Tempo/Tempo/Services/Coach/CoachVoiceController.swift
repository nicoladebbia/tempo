//
// CoachVoiceController.swift
// Tempo
//
// Coach v2.1 Phase 7c — voice-input wrap-up for the chat view.
//
// Thin layer over the existing VoiceTranscriber service. The chat view
// binds to it via a protocol so unit tests can drive transcript state
// without standing up an AVAudioEngine + speech recognizer.
//
// User-configurable mic mode comes from UserSettings.coachVoiceMode
// (set by the interview / Settings — Q2 decision: default tapToggle).
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §"Voice flow (7.11)".
//

import Foundation
import SwiftUI

// MARK: - Protocol

/// Minimal surface the chat view needs from a voice controller.
/// `@MainActor` because mutating live transcription state from a
/// background queue would race the SwiftUI binding.
@MainActor
protocol CoachVoiceControlling: AnyObject {
    /// Live transcription. Updated as partials arrive; consumed by
    /// CoachInputBar to populate the text field.
    var transcribedText: String { get }
    /// True between `start` and `stop` / auto-stop.
    var isListening: Bool { get }
    /// Human-readable error from the last failed `start()`. nil → clear.
    var error: String? { get }

    func start() async
    func stop()
}

// MARK: - Adapter

/// Real implementation. Wraps VoiceTranscriber. The chat view stores
/// this as `any CoachVoiceControlling` so test code can swap in a stub.
@MainActor
@Observable
final class CoachVoiceController: CoachVoiceControlling {
    private let transcriber: VoiceTranscriber

    /// Reflects transcriber.transcribedText. Updated by an observation
    /// callback the SwiftUI binding will pick up. We expose transcribedText
    /// directly off the underlying transcriber via computed access.
    var transcribedText: String { transcriber.transcribedText }
    var isListening: Bool { transcriber.isListening }
    var error: String? { transcriber.error }

    init(transcriber: VoiceTranscriber = VoiceTranscriber()) {
        self.transcriber = transcriber
    }

    func start() async {
        await transcriber.start()
    }

    func stop() {
        transcriber.stop()
    }
}

// MARK: - Stub for previews / tests

/// Deterministic stub. Tests + SwiftUI previews use this; the chat view
/// can't tell the difference because both conform to the same protocol.
@MainActor
@Observable
final class StubCoachVoiceController: CoachVoiceControlling {
    var transcribedText: String = ""
    var isListening: Bool = false
    var error: String?

    /// When true, `start()` synchronously sets isListening = true so
    /// view-driven UI state can flip during tests.
    var simulatePartial: String?

    func start() async {
        isListening = true
        if let partial = simulatePartial {
            transcribedText = partial
        }
    }

    func stop() {
        isListening = false
    }
}
