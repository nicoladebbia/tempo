@testable import App
import Foundation
import Testing

// MARK: - Program-import request decoding

//
// iOS sends snake_case (`session_id`, `hint_texts`, …) and the app's global
// JSON decoder uses `.convertFromSnakeCase` — which maps `session_id` to
// `sessionId`, never `sessionID`. Pin that both import requests decode.

@Suite("ProgramImportRequestDecoding")
struct ProgramImportRequestDecodingTests {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @Test func transcribeRequestDecodesFromSnakeCase() throws {
        let id = UUID().uuidString
        let json = """
        {"session_id":"\(id)","images":[{"media_type":"image/jpeg","base64":"AAAA"}],
         "hint_texts":["page 1"],"system":"s","user_message":"u"}
        """
        let request = try decoder().decode(ProgramImportTranscribeRequest.self, from: Data(json.utf8))
        #expect(request.sessionID == id)
        #expect(request.images.first?.mediaType == "image/jpeg")
        #expect(request.hintTexts == ["page 1"])
        #expect(request.userMessage == "u")
    }

    @Test func structureRequestDecodesFromSnakeCase() throws {
        let id = UUID().uuidString
        let json = """
        {"session_id":"\(id)","model":"sonnet","system":"s","user_message":"u",
         "max_tokens":4000,"temperature":0.2,"caller":"trainer_program_import"}
        """
        let request = try decoder().decode(ProgramImportStructureRequest.self, from: Data(json.utf8))
        #expect(request.sessionID == id)
        #expect(request.maxTokens == 4000)
    }

    /// trainer-feedback-tests — the "feedback" route's request has no
    /// acronym/ID field (unlike transcribe/structure's `session_id`), so it
    /// needs no explicit CodingKeys — pin that `.convertFromSnakeCase` alone
    /// is enough for it to decode correctly.
    @Test func feedbackRequestDecodesFromSnakeCase() throws {
        let json = """
        {"model":"sonnet","system":"s","user_message":"u",
         "max_tokens":1500,"temperature":0,"caller":"trainer_feedback_edit"}
        """
        let request = try decoder().decode(ProgramFeedbackRequest.self, from: Data(json.utf8))
        #expect(request.model == "sonnet")
        #expect(request.userMessage == "u")
        #expect(request.maxTokens == 1500)
        #expect(request.caller == "trainer_feedback_edit")
    }
}

@Suite("DeviceTokenRegisterDecoding")
struct DeviceTokenRegisterDecodingTests {
    @Test func registerRequestDecodesFromSnakeCase() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"token":"abc","device_id":"dev-1","device_name":"iPhone","app_version":"1.0"}"#
        let dto = try decoder.decode(DeviceTokenRegisterDTO.self, from: Data(json.utf8))
        #expect(dto.deviceID == "dev-1")
        #expect(dto.deviceName == "iPhone")
        #expect(dto.appVersion == "1.0")
    }
}
