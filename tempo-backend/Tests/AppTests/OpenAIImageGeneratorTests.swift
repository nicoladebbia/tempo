@testable import App
import Foundation
import Testing

// MARK: - OpenAIImageGenerator

//
// These tests never touch the network — OpenAIImageGenerator.generateImage
// itself isn't exercised here (that needs req.client + Postgres to test
// meaningfully, skipped per "no local Postgres running"). What IS covered,
// with zero DB/network dependency:
//   - The request DTO encodes to the exact wire shape OpenAI's API expects.
//   - The response DTO decodes a realistic fixture (data[0].b64_json).
//   - The "not configured" gate (OPENAI_API_KEY unset) is a pure function.

@Suite("OpenAIImageGenerator request encoding")
struct OpenAIImageGenerationRequestTests {
    @Test func encodesToSnakeCaseWireShape() throws {
        let request = OpenAIImageGenerationRequest(
            model: "gpt-image-1",
            prompt: "a barbell back squat",
            size: "1536x1024",
            quality: "medium",
            outputFormat: "jpeg",
            outputCompression: 85,
            n: 1
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["model"] as? String == "gpt-image-1")
        #expect(json["prompt"] as? String == "a barbell back squat")
        #expect(json["size"] as? String == "1536x1024")
        #expect(json["quality"] as? String == "medium")
        #expect(json["output_format"] as? String == "jpeg")
        #expect(json["output_compression"] as? Int == 85)
        #expect(json["n"] as? Int == 1)
    }
}

@Suite("OpenAIImageGenerator response decoding")
struct OpenAIImageGenerationResponseTests {
    @Test func decodesB64JsonFromFixture() throws {
        // Fixture shape per OpenAI's current /v1/images/generations response
        // (verified 2026-09-25 against developers.openai.com's API reference
        // mirror — see OpenAIImageGenerator.swift header comment). gpt-image-1
        // always returns b64_json, never "url".
        let fixture = """
        {
          "created": 1713833628,
          "data": [
            { "b64_json": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" }
          ],
          "usage": { "total_tokens": 100, "input_tokens": 50, "output_tokens": 50 }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenAIImageGenerationResponse.self, from: Data(fixture.utf8))

        #expect(response.data.count == 1)
        let b64 = try #require(response.data.first?.b64Json)
        let imageData = try #require(Data(base64Encoded: b64))
        #expect(!imageData.isEmpty)
    }

    @Test func decodesEmptyDataArray() throws {
        let fixture = #"{"data": []}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenAIImageGenerationResponse.self, from: Data(fixture.utf8))
        #expect(response.data.isEmpty)
    }
}

@Suite("OpenAIImageGenerator.isConfigured", .serialized)
struct OpenAIImageGeneratorConfiguredTests {
    @Test func falseWhenKeyMissing() {
        unsetenv("OPENAI_API_KEY")
        #expect(OpenAIImageGenerator.isConfigured == false)
    }

    @Test func falseWhenKeyEmpty() {
        setenv("OPENAI_API_KEY", "", 1)
        defer { unsetenv("OPENAI_API_KEY") }
        #expect(OpenAIImageGenerator.isConfigured == false)
    }

    @Test func trueWhenKeySet() {
        setenv("OPENAI_API_KEY", "sk-test-key", 1)
        defer { unsetenv("OPENAI_API_KEY") }
        #expect(OpenAIImageGenerator.isConfigured == true)
    }
}
