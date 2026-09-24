@testable import App
import Foundation
import Testing

// MARK: - ProgramImportTranscribeValidation tests

//
// Pure — no Request/DB — validation the transcribe route runs before
// touching the quota gate or the network.

@Suite("ProgramImportTranscribeValidation")
struct ProgramImportTranscribeValidationTests {
    @Test func validRequestPasses() throws {
        try ProgramImportTranscribeValidation.validate(
            sessionID: UUID().uuidString,
            imageCount: 3,
            hintTextsCount: 3,
            rawByteEstimate: 1024 * 1024
        )
    }

    @Test func validRequestWithNoHintTextsPasses() throws {
        try ProgramImportTranscribeValidation.validate(
            sessionID: UUID().uuidString,
            imageCount: 5,
            hintTextsCount: 0,
            rawByteEstimate: 1024
        )
    }

    @Test func rejectsNonUUIDSessionID() {
        #expect(throws: ProgramImportTranscribeValidation.ValidationError.invalidSessionID) {
            try ProgramImportTranscribeValidation.validate(
                sessionID: "not-a-uuid",
                imageCount: 1,
                hintTextsCount: 0,
                rawByteEstimate: 100
            )
        }
    }

    @Test func rejectsZeroImages() {
        #expect(throws: ProgramImportTranscribeValidation.ValidationError.imageCountOutOfRange(count: 0)) {
            try ProgramImportTranscribeValidation.validate(
                sessionID: UUID().uuidString,
                imageCount: 0,
                hintTextsCount: 0,
                rawByteEstimate: 0
            )
        }
    }

    @Test func rejectsMoreThanFiveImages() {
        #expect(throws: ProgramImportTranscribeValidation.ValidationError.imageCountOutOfRange(count: 6)) {
            try ProgramImportTranscribeValidation.validate(
                sessionID: UUID().uuidString,
                imageCount: 6,
                hintTextsCount: 0,
                rawByteEstimate: 100
            )
        }
    }

    @Test func rejectsHintTextsLengthMismatch() {
        #expect(throws: ProgramImportTranscribeValidation.ValidationError.hintTextsLengthMismatch(hintTextsCount: 2, imageCount: 3)) {
            try ProgramImportTranscribeValidation.validate(
                sessionID: UUID().uuidString,
                imageCount: 3,
                hintTextsCount: 2,
                rawByteEstimate: 100
            )
        }
    }

    @Test func rejectsOversizedBatch() {
        let max = TrainingProgramImportController.maxRawImageBytesPerRequest
        #expect(throws: ProgramImportTranscribeValidation.ValidationError.batchTooLarge(rawByteEstimate: max + 1, maxBytes: max)) {
            try ProgramImportTranscribeValidation.validate(
                sessionID: UUID().uuidString,
                imageCount: 2,
                hintTextsCount: 0,
                rawByteEstimate: max + 1
            )
        }
    }

    @Test func exactlyAtByteBudgetPasses() throws {
        let max = TrainingProgramImportController.maxRawImageBytesPerRequest
        try ProgramImportTranscribeValidation.validate(
            sessionID: UUID().uuidString,
            imageCount: 1,
            hintTextsCount: 0,
            rawByteEstimate: max
        )
    }

    @Test func rawByteCountApproximatesBase64Overhead() {
        // A base64 string of 4*N chars decodes to ~3*N raw bytes.
        let base64 = String(repeating: "A", count: 4000)
        #expect(TrainingProgramImportController.rawByteCount(fromBase64: base64) == 3000)
    }
}
