import Foundation
import Vapor

// MARK: - OpenAIImageGenerator

//
// Real ExerciseImageGenerating implementation. Calls
// POST https://api.openai.com/v1/images/generations with model "gpt-image-1".
//
// Request/response shape verified 2026-09-25 against OpenAI's current API
// reference (platform.openai.com/docs/api-reference/images/create, mirrored
// at developers.openai.com after a doc-site redirect) and the image-generation
// guide (platform.openai.com/docs/guides/image-generation):
//   - Request fields: model, prompt, size ("auto" | "1024x1024" | "1536x1024" |
//     "1024x1536"), quality ("auto" | "low" | "medium" | "high"),
//     output_format ("png" | "jpeg" | "webp"), output_compression (0-100,
//     jpeg/webp only), n (1-10). All snake_case over the wire.
//   - Response: { "data": [ { "b64_json": "<base64>" } ], "usage": {...} }.
//     gpt-image-1 always returns b64_json (no "url"/response_format knob like
//     dall-e-3) — decode data[0].b64_json per the task spec.
//   - quality "medium" + size "1536x1024" is documented at ~$0.04/image.
//
// NEVER invoked with a real key in tests — see ExerciseImageGenerating.swift.

struct OpenAIImageGenerator: ExerciseImageGenerating {
    static let model = "gpt-image-1"
    static let size = "1536x1024"
    static let quality = "medium"
    static let outputFormat = "jpeg"
    static let outputCompression = 85
    static let costCents = 4

    /// True once OPENAI_API_KEY is set. Pure/no Request dependency so it's
    /// unit-testable without booting an Application.
    static var isConfigured: Bool {
        guard let key = Environment.get("OPENAI_API_KEY") else { return false }
        return !key.isEmpty
    }

    func generateImage(prompt: String, on req: Request) async throws -> GeneratedExerciseImage {
        guard Self.isConfigured, let apiKey = Environment.get("OPENAI_API_KEY") else {
            throw ExerciseImageGenerationError.notConfigured
        }

        let body = OpenAIImageGenerationRequest(
            model: Self.model,
            prompt: prompt,
            size: Self.size,
            quality: Self.quality,
            outputFormat: Self.outputFormat,
            outputCompression: Self.outputCompression,
            n: 1
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(body)

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: .authorization, value: "Bearer \(apiKey)")

        let response = try await req.client.post(
            URI(string: "https://api.openai.com/v1/images/generations"),
            headers: headers
        ) { clientReq in
            clientReq.body = .init(data: bodyData)
        }

        guard response.status == .ok else {
            req.logger.error("[exercise_image] OpenAI HTTP \(response.status.code)")
            throw ExerciseImageGenerationError.apiError(Int(response.status.code))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw: OpenAIImageGenerationResponse
        do {
            raw = try response.content.decode(OpenAIImageGenerationResponse.self, using: decoder)
        } catch {
            req.logger.error("[exercise_image] decode failed: \(error)")
            throw ExerciseImageGenerationError.decodingFailed
        }

        guard let b64 = raw.data.first?.b64Json,
              let imageData = Data(base64Encoded: b64)
        else {
            throw ExerciseImageGenerationError.decodingFailed
        }

        return GeneratedExerciseImage(data: imageData, contentType: "image/jpeg")
    }
}

// MARK: - Wire DTOs

struct OpenAIImageGenerationRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let size: String
    let quality: String
    let outputFormat: String
    let outputCompression: Int
    let n: Int
}

struct OpenAIImageGenerationResponse: Decodable, Sendable {
    struct ImageData: Decodable, Sendable {
        let b64Json: String?
    }

    let data: [ImageData]
}
