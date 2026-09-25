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
