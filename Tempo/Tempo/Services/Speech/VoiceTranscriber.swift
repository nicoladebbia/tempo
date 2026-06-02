//
// VoiceTranscriber.swift
// Tempo
//
// Created by Tempo on 12/05/2026.
//
//

import AVFoundation
import Foundation
import os
import Speech

/// Continuous on-device speech recognition for short utterances (a pantry
/// item name, a one-line note). Reports partial results live so the user
/// sees text appear as they speak, and auto-stops after a configurable
/// silence window.
///
/// Lifecycle:
///   1. `start()` requests permission (mic + speech) on first invocation.
///   2. Audio engine + buffer-recognition request start. `transcribedText`
///      mutates as Apple emits partials.
///   3. A debounce timer resets on every partial. When no new partial arrives
///      for `silenceTimeout`, transcription auto-stops.
///   4. `stop()` (manual or auto) tears down audio + cancels the recognition.
@Observable
@MainActor
final class VoiceTranscriber {
    /// Live transcription. Updated on partial results.
    private(set) var transcribedText: String = ""

    /// True between `start()` and `stop()` / auto-stop.
    private(set) var isListening: Bool = false

    /// Human-readable error from the last `start()` attempt, if any.
    private(set) var error: String?

    /// How long without a new partial result before we auto-stop. 4s gives
    /// the user time to pause and think mid-sentence (e.g. listing a
    /// multi-ingredient meal) without being cut off. Tap the stop button
    /// for an immediate end.
    var silenceTimeout: TimeInterval = 4.0

    /// Continuous-dictation mode. When true, the recognizer's periodic
    /// `isFinal` segment-finalizations do NOT stop recording (Apple finalizes
    /// a segment mid-speech and starts a fresh task; for a long pantry
    /// stock-take we must keep going until the user taps Stop). When false
    /// (meal-log's short-utterance default), the first `isFinal` ends capture.
    var continuousMode: Bool = false

    private let logger = Logger(subsystem: "app.tempo", category: "VoiceTranscriber")
    /// Prefer the user's current locale (so an Italian user gets Italian
    /// recognition out of the box). Fall back to en_US when the system locale
    /// doesn't have a recognizer model available.
    private let recognizer: SFSpeechRecognizer? = {
        if let current = SFSpeechRecognizer(locale: Locale.current), current.isAvailable {
            return current
        }
        return SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    }()

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    /// Continuous-mode: text of each completed segment, joined for the full
    /// transcript so a mid-speech recognizer rollover doesn't drop earlier
    /// words. `currentSegment` is the in-progress segment (not yet committed).
    private var committedSegments: [String] = []
    private var currentSegment = ""

    /// Begin transcription. Idempotent — calls while listening are no-ops.
    func start() async {
        guard !isListening else {
            return
        }
        error = nil
        transcribedText = ""
        committedSegments = []
        currentSegment = ""

        guard await requestPermissions() else {
            error = "Speech recognition not authorized."
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition unavailable."
            return
        }

        do {
            try configureAudioSession()
            try startEngine(with: recognizer)
            isListening = true
        } catch {
            self.error = error.localizedDescription
            logger.error("Speech start failed: \(error.localizedDescription)")
            cleanup()
        }
    }

    /// Stop transcription. Safe to call at any time.
    func stop() {
        guard isListening else {
            return
        }
        cleanup()
    }

    // MARK: - Permissions

    private nonisolated func requestPermissions() async -> Bool {
        // Both TCC callbacks fire on `com.apple.root.default-qos`, NOT the
        // main actor. If this method (or its continuation closures) inherits
        // @MainActor isolation from the enclosing class, Swift 6 strict
        // concurrency trips `_swift_task_checkIsolatedSwift` →
        // dispatch_assert_queue_fail the moment the callback runs. Marking
        // the method nonisolated keeps the resume off the main actor.
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            return false
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - Audio engine

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startEngine(with recognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Reset any previously-installed tap so reruns don't crash on duplicate install.
        inputNode.removeTap(onBus: 0)
        // The tap closure fires on the real-time audio render thread
        // (`RealtimeMessenger.mServiceQueue`). If the closure inherits
        // @MainActor isolation from the enclosing class, Swift 6 strict
        // concurrency runs `_swift_task_checkIsolatedSwift` on entry and
        // trips dispatch_assert_queue_fail. Hoist the tap block into an
        // explicit @Sendable function value so it has no actor isolation.
        nonisolated(unsafe) let tapRequest = request
        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            tapRequest.append(buffer)
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapBlock)

        audioEngine.prepare()
        try audioEngine.start()

        // Same isolation hazard as the tap block: this callback runs on
        // Apple's recognition queue, not the main actor. Declare it
        // @Sendable so it doesn't inherit @MainActor from the enclosing
        // class, then hop back to MainActor inside.
        let taskHandler: @Sendable (SFSpeechRecognitionResult?, Error?) -> Void = { [weak self] result, error in
            // Extract Sendable values on Apple's recognition queue — the
            // result object itself is not Sendable, so don't capture it.
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if let transcript {
                    if self.continuousMode {
                        // Apple's recognizer rolls its internal segment over on
                        // long utterances — `formattedString` SILENTLY resets to
                        // just the new segment, often WITHOUT an isFinal flag
                        // (observed: a 338-char transcript dropping to "Whatever"
                        // on a non-final partial). A rollover shows up as the new
                        // text not extending the previous segment. When that
                        // happens, COMMIT the previous segment before adopting the
                        // new one, so nothing earlier is lost.
                        self.transcribedText = self.applyContinuousPartial(transcript, isFinal: isFinal)
                        // Do NOT stop on isFinal in continuous mode — only the
                        // user's Stop tap ends the session.
                        self.resetSilenceTimer()
                    } else {
                        self.transcribedText = transcript
                        self.resetSilenceTimer()
                        if isFinal {
                            self.stop()
                        }
                    }
                }
                if let errorDescription {
                    self.logger.warning("Recognition error: \(errorDescription)")
                    self.stop()
                }
            }
        }
        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: taskHandler)

        resetSilenceTimer()
    }

    /// Fraction of the current segment's length below which a new non-final
    /// partial is treated as a recognizer ROLLOVER (segment reset) rather than
    /// a revision. A fresh recognition session always starts short and grows,
    /// so a rollover always shows up as a dramatic collapse. Ordinary
    /// revisions (homophone/number fixes) change length only slightly and stay
    /// in-segment. 0.6 = "lost >40% of the text" → rollover.
    static let rolloverCollapseFraction = 0.6

    /// Folds one continuous-mode partial into the segment accumulator and
    /// returns the full assembled transcript. Pure over the segment state
    /// (no audio, no actor hops) so the exact device partial stream can be
    /// replayed in a unit test. See VoiceTranscriberContinuousTests.
    @discardableResult
    func applyContinuousPartial(_ transcript: String, isFinal: Bool) -> String {
        let prev = currentSegment
        // Collapse detection: a non-final partial that drops below
        // rolloverCollapseFraction of the previous length is a rollover — bank
        // the previous segment before adopting the new (fresh) one.
        let collapsed = !prev.isEmpty
            && Double(transcript.count) < Double(prev.count) * Self.rolloverCollapseFraction
        if collapsed {
            committedSegments.append(prev)
        }
        if isFinal {
            committedSegments.append(transcript)
            currentSegment = ""
        } else {
            currentSegment = transcript
        }
        let parts = committedSegments + (currentSegment.isEmpty ? [] : [currentSegment])
        return parts.joined(separator: " ")
    }

    /// Restarts the silence countdown. Called on every partial result.
    /// A `silenceTimeout <= 0` disables auto-stop entirely — the caller is
    /// responsible for stopping (used by voice pantry, where the user lists
    /// many items with natural pauses and ends by tapping Stop).
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        guard silenceTimeout > 0 else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }

    private func cleanup() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        // Signal end-of-audio so the recognition task drains naturally.
        // Calling `cancel()` after `endAudio()` makes Apple's internal
        // accumulator complain ("update accumulator after completion"
        // warnings) because results queued behind endAudio can't be
        // delivered. Only `cancel()` when the task hasn't finished —
        // i.e. when we genuinely need to abandon mid-stream rather
        // than wait for the final result.
        recognitionRequest?.endAudio()
        if let task = recognitionTask, task.state != .completed && task.state != .finishing {
            task.finish()
        }
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
    }
}
