//
// DailySessionDTO.swift
// Tempo
//
// The daily-training-brain AI output contract (docs/INTELLIGENT_TRAINING_SYSTEM.md
// §13.1). camelCase wire format — NEVER touches the snake_case SwiftData DTOs.
// Claude returns this as JSON; the parser enforces the per-kind required contract
// and ANY failure invalidates the WHOLE session → caller falls back to the
// deterministic floor's own pick. Never render a half-parsed session.
//
// Design note (§13.1): `block` is a FLAT object with a `kind` discriminator +
// optional per-kind fields, NOT a tagged enum. Haiku mangles nested {gym:{...}};
// a flat struct with optionals parses with one Codable + retries reliably.
//
// CRITICAL (§13.1, §8 KEEP): a gym block is a POINTER, not a prescription —
// `{kind:gym, split:push}` only. The existing engine (populateExercises) fills
// exercises/sets/weights and writes PredictionLog. The AI must NOT emit gym
// weights — they'd fight AIProgramPlanner.reconcile's [0.5,1.1] clamp and bypass
// the RPE accuracy loop.
//

import Foundation

// MARK: - Intensity

enum SessionIntensity: String, Codable, Sendable, CaseIterable {
    case recovery
    case easy
    case moderate
    case hard
    case max
}

// MARK: - BlockKind

enum BlockKind: String, Codable, Sendable, CaseIterable {
    case gym
    case field
    case pool
    case run
    case bodyweight
    case mobility
    case rest
}

// MARK: - SessionBlockDTO

/// Flat block: a `kind` discriminator plus optional per-kind fields. The parser
/// (`validate()`) enforces which fields are REQUIRED for each kind.
struct SessionBlockDTO: Codable, Sendable, Equatable {
    let kind: BlockKind
    let label: String
    let notes: String?
    /// Short technique cue per movement/drill (§14 Decision 4). AI-generated.
    let cue: String?
    /// §21 two-a-day: minutes after midnight this block's PART starts. Blocks
    /// sharing a scheduledMin form one part ("PULL @16:00 + FIELD @20:00");
    /// nil joins the session's first part. Optional + additive — old persisted
    /// rows and single-part sessions decode unchanged.
    let scheduledMin: Int?

    // gym → pointer only
    let split: String?

    // field
    let reps: Int?
    let distanceM: Double?
    let restSec: Int?
    let intensityPct: Double?

    // pool / run shared
    let durationSec: Int?
    let stroke: String?
    let runType: String?
    let paceSecPerKm: Double?

    // bodyweight
    let sets: Int?
}

// MARK: - DailySessionDTO

/// The top-level AI-emitted session. `expectedStrain` / `expectedSessionRPE` are
/// the predictions the per-modality outcome loop scores (§13.2).
struct DailySessionDTO: Codable, Sendable, Equatable {
    let modality: String
    let intensity: SessionIntensity
    let durationMin: Int
    let blocks: [SessionBlockDTO]
    let shortWhy: String
    let fullWhy: String?
    let expectedStrain: Double?
    let expectedSessionRPE: Int?
}

extension Array where Element == SessionBlockDTO {
    /// §21 two-a-day: blocks grouped into time-tagged PARTS, ordered by start.
    /// Untimed blocks form/join the first part (back-compat: a pre-§21 session
    /// is exactly one untimed part). The floor's composite rules and the card's
    /// grouped render both read this — one grouping definition, not two. Lives
    /// on the block array so the persisted DailySession's decoded blocks get it
    /// for free.
    var parts: [(scheduledMin: Int?, blocks: [SessionBlockDTO])] {
        var timed: [Int: [SessionBlockDTO]] = [:]
        var untimed: [SessionBlockDTO] = []
        for block in self {
            if let min = block.scheduledMin {
                timed[min, default: []].append(block)
            } else {
                untimed.append(block)
            }
        }
        let timedParts = timed.keys.sorted().map { (Optional($0), timed[$0]!) }
        guard !untimed.isEmpty else { return timedParts }
        guard !timedParts.isEmpty else { return [(nil, untimed)] }
        // Untimed blocks join the EARLIEST part — the anchor.
        var merged = timedParts
        merged[0] = (merged[0].0, untimed + merged[0].1)
        return merged
    }
}

extension DailySessionDTO {
    /// §21 — see `[SessionBlockDTO].parts`.
    var parts: [(scheduledMin: Int?, blocks: [SessionBlockDTO])] { blocks.parts }

    /// True when the session prescribes two or more time-separated parts.
    var isComposite: Bool { parts.count >= 2 }
}

// MARK: - Parse errors

enum DailySessionParseError: Error, Equatable {
    case notValidJSON
    case decodeFailed(String)
    case emptyBlocks
    case shortWhyMissingOrTooLong
    case blockContractViolated(kind: BlockKind, missing: String)
    case intensityOutOfRange
}

// MARK: - Parser

/// Parses + validates a raw Claude response into a DailySessionDTO, or throws.
/// A throw is the SIGNAL to fall back to the deterministic floor (§5.2-FIX,
/// §13.1) — never render a partially-valid session.
enum DailySessionParser {

    /// Strips an optional markdown code fence and any prose preamble/suffix,
    /// then decodes the first balanced top-level JSON object. Haiku at temp 0.6
    /// sometimes wraps JSON in ```json fences or adds a sentence — tolerate that,
    /// but reject anything that isn't a clean object once extracted.
    static func parse(_ raw: String) throws -> DailySessionDTO {
        guard let jsonData = extractJSONObject(from: raw) else {
            throw DailySessionParseError.notValidJSON
        }

        let decoded: DailySessionDTO
        do {
            decoded = try JSONDecoder().decode(DailySessionDTO.self, from: jsonData)
        } catch {
            throw DailySessionParseError.decodeFailed(String(describing: error))
        }

        // COERCE cosmetic overflow, don't hard-fail it. A 130-char shortWhy is a
        // complete, correct session — throwing it to the dumber deterministic
        // fallback would be a self-inflicted wound (and the next slightly-long
        // title would nuke the next good session too). Match severity to the
        // field: structural failures (bad JSON, missing block fields, bad enum)
        // hard-fail; a moderately-long TITLE renders in full (the card wraps),
        // and only a pathological one is word-cut. (§13.1 "never render
        // half-parsed" — a long title is not half-parsed.)
        let coerced = coerce(decoded)

        try validate(coerced)
        return coerced
    }

    /// Display ceiling for shortWhy. The PROMPT still asks for ≤120 (brevity is
    /// the model's job); a moderate overrun is shown IN FULL — the card wraps,
    /// and a mid-word "…" cut reads worse than an extra line (the live 2026-06-09
    /// complaint: "Preserve progres…"). Only a pathological dump (the model
    /// putting fullWhy-sized prose in the title) is cut, and at a word boundary.
    static let shortWhyDisplayCap = 240

    /// Repairs cosmetic-only deviations so a structurally-sound session survives.
    /// Currently: word-boundary truncation of a pathologically long shortWhy
    /// (> shortWhyDisplayCap). Anything under the cap passes through verbatim.
    static func coerce(_ session: DailySessionDTO) -> DailySessionDTO {
        guard session.shortWhy.count > shortWhyDisplayCap else { return session }
        var head = String(session.shortWhy.prefix(shortWhyDisplayCap - 1))
        // Drop the trailing partial word — the cut must land on whole words.
        if let lastSpace = head.lastIndex(of: " ") {
            head = String(head[..<lastSpace])
        }
        let trimmed = head.trimmingCharacters(in: .whitespaces) + "…"
        return DailySessionDTO(
            modality: session.modality, intensity: session.intensity,
            durationMin: session.durationMin, blocks: session.blocks,
            shortWhy: trimmed, fullWhy: session.fullWhy,
            expectedStrain: session.expectedStrain, expectedSessionRPE: session.expectedSessionRPE
        )
    }

    /// Enforces the per-kind required contract (§13.1). Pure; testable in isolation.
    static func validate(_ session: DailySessionDTO) throws {
        guard !session.blocks.isEmpty else { throw DailySessionParseError.emptyBlocks }
        // Empty shortWhy is structural (the model gave NO rationale) → hard-fail.
        // Over-length up to the display cap is fine (shown in full — the card
        // wraps); beyond it parse() has already word-cut in coerce(). validate
        // stays strict for direct callers (they should coerce first).
        guard !session.shortWhy.isEmpty,
              session.shortWhy.count <= DailySessionParser.shortWhyDisplayCap else {
            throw DailySessionParseError.shortWhyMissingOrTooLong
        }
        if let rpe = session.expectedSessionRPE, !(1 ... 10).contains(rpe) {
            throw DailySessionParseError.intensityOutOfRange
        }

        for block in session.blocks {
            switch block.kind {
            case .gym:
                // POINTER only — split required, NO weights (the engine fills those).
                guard let s = block.split, !s.isEmpty else {
                    throw DailySessionParseError.blockContractViolated(kind: .gym, missing: "split")
                }
            case .field:
                guard block.reps != nil || block.distanceM != nil else {
                    throw DailySessionParseError.blockContractViolated(kind: .field, missing: "reps|distanceM")
                }
            case .pool:
                guard block.distanceM != nil || block.durationSec != nil else {
                    throw DailySessionParseError.blockContractViolated(kind: .pool, missing: "distanceM|durationSec")
                }
            case .run:
                guard let rt = block.runType, !rt.isEmpty else {
                    throw DailySessionParseError.blockContractViolated(kind: .run, missing: "runType")
                }
                guard block.distanceM != nil || block.durationSec != nil else {
                    throw DailySessionParseError.blockContractViolated(kind: .run, missing: "distanceM|durationSec")
                }
            case .bodyweight:
                guard block.reps != nil || block.durationSec != nil else {
                    throw DailySessionParseError.blockContractViolated(kind: .bodyweight, missing: "reps|durationSec")
                }
            case .mobility, .rest:
                break // label suffices
            }
        }
    }

    // MARK: - JSON extraction

    /// Returns the bytes of the first balanced `{...}` object in `raw`, tolerating
    /// a ```json fence and surrounding prose. Brace-counting (not regex) so nested
    /// objects survive. nil when no balanced object exists.
    static func extractJSONObject(from raw: String) -> Data? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIdx = trimmed.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var endIdx: String.Index?

        var i = startIdx
        while i < trimmed.endIndex {
            let c = trimmed[i]
            if escaped {
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "\"" {
                inString.toggle()
            } else if !inString {
                if c == "{" {
                    depth += 1
                } else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIdx = i
                        break
                    }
                }
            }
            i = trimmed.index(after: i)
        }

        guard let end = endIdx else { return nil }
        let slice = trimmed[startIdx ... end]
        return String(slice).data(using: .utf8)
    }
}
