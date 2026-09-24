//
// TrainerProgramImportDTOs.swift
// Tempo
//
// iOS-side DTOs + endpoint definitions for the Trainer Program import routes
// (fix #1 + #2): the import no longer rides the Pro-only nutrition AI proxy
// (POST /v1/nutrition/ai/proxy/*) — it has its own backend routes with a
// free-tier monthly quota instead of a hard Pro wall, and a batched
// multi-image transcribe call instead of one request per page.
//

import Foundation

// MARK: - ProgramImportImageInputDTO

/// Mirrors backend `ProgramImportImageInput`.
struct ProgramImportImageInputDTO: Codable, Sendable {
    /// e.g. "image/jpeg", "image/png", "image/webp"
    let mediaType: String
    /// Base64-encoded image bytes (no data: prefix).
    let base64: String

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case base64
    }
}

// MARK: - ProgramImportTranscribeRequestDTO

/// Mirrors backend `ProgramImportTranscribeRequest`.
struct ProgramImportTranscribeRequestDTO: Codable, Sendable {
    /// Client-generated UUID shared by every call in ONE import (every
    /// transcribe batch + the structure call) — used server-side for quota
    /// dedup so a retry never burns a second slot.
    let sessionID: String
    let images: [ProgramImportImageInputDTO]
    /// Per-image on-device text hint, same length as `images`, or empty for
    /// "no hints at all".
    let hintTexts: [String?]
    let system: String
    let userMessage: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case images
        case hintTexts = "hint_texts"
        case system
        case userMessage = "user_message"
    }
}

// MARK: - ProgramImportTranscribeResponseDTO

/// Mirrors backend `ProgramImportTranscribeResponse`.
struct ProgramImportTranscribeResponseDTO: Codable, Sendable {
    /// One entry per page, in the order the images were sent.
    let pages: [String]
}

// MARK: - ProgramImportStructureRequestDTO

/// Mirrors backend `ProgramImportStructureRequest`.
struct ProgramImportStructureRequestDTO: Codable, Sendable {
    let sessionID: String
    /// One of: "haiku", "sonnet". The structure step always sends "sonnet".
    let model: String
    let system: String
    let userMessage: String
    let maxTokens: Int
    let temperature: Double
    let caller: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case model
        case system
        case userMessage = "user_message"
        case maxTokens = "max_tokens"
        case temperature
        case caller
    }
}

// MARK: - ProgramImportStructureResponseDTO

/// Mirrors backend `ProgramImportStructureResponse`.
struct ProgramImportStructureResponseDTO: Codable, Sendable {
    let text: String
}

// MARK: - ProgramImportQuotaResponseDTO

/// Mirrors backend `ProgramImportQuotaResponse`. `limit`/`remaining` are nil
/// for Pro/allowlisted (unlimited) users.
struct ProgramImportQuotaResponseDTO: Codable, Sendable {
    let isPro: Bool
    let limit: Int?
    let used: Int
    let remaining: Int?
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case isPro = "is_pro"
        case limit
        case used
        case remaining
        case resetsAt = "resets_at"
    }
}

// MARK: - APIEndpoint extensions

extension APIEndpoint where Response == ProgramImportTranscribeResponseDTO {
    static func trainerProgramImportTranscribe() -> Self {
        APIEndpoint(path: "/v1/training/program-import/transcribe", method: .post)
    }
}

extension APIEndpoint where Response == ProgramImportStructureResponseDTO {
    static func trainerProgramImportStructure() -> Self {
        APIEndpoint(path: "/v1/training/program-import/structure", method: .post)
    }
}

extension APIEndpoint where Response == ProgramImportQuotaResponseDTO {
    static func trainerProgramImportQuota() -> Self {
        APIEndpoint(path: "/v1/training/program-import/quota", method: .get)
    }
}
