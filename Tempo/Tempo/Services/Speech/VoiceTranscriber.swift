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

    /// How long without a new partial result before we auto-stop.
    var silenceTimeout: TimeInterval = 1.5

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

    /// Begin transcription. Idempotent — calls while listening are no-ops.
    func start() async {
        guard !isListening else {
            return
        }
        error = nil
        transcribedText = ""

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

    private func requestPermissions() async -> Bool {
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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal {
                        self.stop()
                    }
                }
                if let error {
                    self.logger.warning("Recognition error: \(error.localizedDescription)")
                    self.stop()
                }
            }
        }

        resetSilenceTimer()
    }

    /// Restarts the silence countdown. Called on every partial result.
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
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
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
    }
}
