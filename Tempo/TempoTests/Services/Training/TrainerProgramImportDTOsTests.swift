//
// TrainerProgramImportDTOsTests.swift
// Tempo
//
// Wire-format tests for the Trainer Program import DTOs (fix #1 + #2): the
// backend encodes with `keyEncodingStrategy = .convertToSnakeCase` and
// `dateEncodingStrategy = .iso8601`, and APIClient's decoder is configured
// with `.iso8601` too — these pin that both sides agree on field names and
// date format without needing a live server.
//

import Foundation
@testable import Tempo
import XCTest

final class TrainerProgramImportDTOsTests: XCTestCase {
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Quota response decode

    func testDecodesFreeUserQuotaResponse() throws {
        let json = """
        {
            "is_pro": false,
            "limit": 2,
            "used": 1,
            "remaining": 1,
            "resets_at": "2026-10-01T00:00:00Z"
        }
        """
        let dto = try makeDecoder().decode(ProgramImportQuotaResponseDTO.self, from: Data(json.utf8))
        XCTAssertFalse(dto.isPro)
        XCTAssertEqual(dto.limit, 2)
        XCTAssertEqual(dto.used, 1)
        XCTAssertEqual(dto.remaining, 1)
    }

    func testDecodesProUserQuotaResponseWithNullLimitAndRemaining() throws {
        let json = """
        {
            "is_pro": true,
            "limit": null,
            "used": 5,
            "remaining": null,
            "resets_at": "2026-10-01T00:00:00Z"
        }
        """
        let dto = try makeDecoder().decode(ProgramImportQuotaResponseDTO.self, from: Data(json.utf8))
        XCTAssertTrue(dto.isPro)
        XCTAssertNil(dto.limit)
        XCTAssertNil(dto.remaining)
        XCTAssertEqual(dto.used, 5)
    }

    // MARK: - Request encoding (snake_case contract)

    func testTranscribeRequestEncodesSnakeCaseKeys() throws {
        let body = ProgramImportTranscribeRequestDTO(
            sessionID: "abc-123",
            images: [ProgramImportImageInputDTO(mediaType: "image/jpeg", base64: "AAAA")],
            hintTexts: [nil],
            system: "sys",
            userMessage: "msg"
        )
        let data = try makeEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["session_id"] as? String, "abc-123")
        XCTAssertEqual(json?["hint_texts"] as? [String?], [nil])
        XCTAssertNotNil(json?["images"])
        let images = json?["images"] as? [[String: Any]]
        XCTAssertEqual(images?.first?["media_type"] as? String, "image/jpeg")
    }

    func testStructureRequestEncodesSnakeCaseKeys() throws {
        let body = ProgramImportStructureRequestDTO(
            sessionID: "abc-123",
            model: "sonnet",
            system: "sys",
            userMessage: "msg",
            maxTokens: 4096,
            temperature: 0,
            caller: "trainer_program_import"
        )
        let data = try makeEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["session_id"] as? String, "abc-123")
        XCTAssertEqual(json?["max_tokens"] as? Int, 4096)
        XCTAssertEqual(json?["user_message"] as? String, "msg")
    }

    func testTranscribeResponseDecodesPagesArray() throws {
        let json = #"{"pages": ["page one", "page two"]}"#
        let dto = try makeDecoder().decode(ProgramImportTranscribeResponseDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.pages, ["page one", "page two"])
    }

    func testEndpointPathsMatchBackendRoutes() {
        XCTAssertEqual(
            APIEndpoint<ProgramImportTranscribeResponseDTO>.trainerProgramImportTranscribe().path,
            "/v1/training/program-import/transcribe"
        )
        XCTAssertEqual(
            APIEndpoint<ProgramImportStructureResponseDTO>.trainerProgramImportStructure().path,
            "/v1/training/program-import/structure"
        )
        XCTAssertEqual(APIEndpoint<ProgramImportQuotaResponseDTO>.trainerProgramImportQuota().path, "/v1/training/program-import/quota")
    }
}
