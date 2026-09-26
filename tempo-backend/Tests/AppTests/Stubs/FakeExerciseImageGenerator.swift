@testable import App
import Foundation
import Vapor

// MARK: - FakeExerciseImageGenerator

//
// Injected in place of OpenAIImageGenerator wherever a test needs
// ExerciseImageService/ExerciseImageController to succeed (or fail in a
// controlled way) without ever touching the real OpenAI API — there is no
// OPENAI_API_KEY in CI and this codebase must never spend money in tests.

final class FakeExerciseImageGenerator: ExerciseImageGenerating, @unchecked Sendable {
    /// 1x1 transparent pixel, real JPEG bytes — small enough to keep
    /// fixtures/DB rows tiny while still being "real" image data.
    static let onePixelJPEG = Data([
        0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x03, 0x02, 0x02, 0x02, 0x02, 0x02, 0x03, 0x02, 0x02,
        0x02, 0x03, 0x03, 0x03, 0x03, 0x04, 0x06, 0x04, 0x04, 0x04, 0x04, 0x04, 0x08, 0x06, 0x06, 0x05,
        0x06, 0x09, 0x08, 0x0A, 0x0A, 0x09, 0x08, 0x09, 0x09, 0x0A, 0x0C, 0x0F, 0x0C, 0x0A, 0x0B, 0x0E,
        0x0B, 0x09, 0x09, 0x0D, 0x11, 0x0D, 0x0E, 0x0F, 0x10, 0x10, 0x11, 0x10, 0x0A, 0x0C, 0x12, 0x13,
        0x12, 0x10, 0x13, 0x0F, 0x10, 0x10, 0x10, 0xFF, 0xC9, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01,
        0x01, 0x01, 0x11, 0x00, 0xFF, 0xCC, 0x00, 0x06, 0x00, 0x10, 0x10, 0x05, 0xFF, 0xDA, 0x00, 0x08,
        0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xD2, 0xCF, 0x20, 0xFF, 0xD9,
    ])

    enum Mode: Sendable {
        case success
        case notConfigured
        case apiError(Int)
        case decodingFailed
    }

    let mode: Mode
    private let generatedCount = NIOLockedCounter()

    init(mode: Mode = .success) {
        self.mode = mode
    }

    var callCount: Int {
        generatedCount.value
    }

    func generateImage(prompt _: String, on _: Request) async throws -> GeneratedExerciseImage {
        generatedCount.increment()
        switch mode {
        case .success:
            return GeneratedExerciseImage(data: Self.onePixelJPEG, contentType: "image/jpeg")
        case .notConfigured:
            throw ExerciseImageGenerationError.notConfigured
        case let .apiError(code):
            throw ExerciseImageGenerationError.apiError(code)
        case .decodingFailed:
            throw ExerciseImageGenerationError.decodingFailed
        }
    }
}

/// Tiny Sendable counter — avoids pulling in an actor just to count calls
/// from synchronous test assertions.
final class NIOLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }
}
