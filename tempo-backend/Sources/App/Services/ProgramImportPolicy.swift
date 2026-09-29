import Foundation

// MARK: - ProgramImportPolicy

//
// Server-side guardrails for the trainer program-import routes. The iOS app
// used to control the model, system prompt, token budget, temperature and
// caller tag of every Claude call these routes make, so any authenticated
// (even free) user could use them as an unmetered Claude proxy. Now:
//
//  - model: allowlist (the app only ever sends "sonnet"); anything else -> 400.
//  - system prompt: SERVER-OWNED. The client's `system` field is accepted (so
//    old/new app builds keep decoding) but ignored. These strings mirror
//    TrainerProgramParser / TrainerFeedbackParser / TrainerProgramPageTranscriber
//    `systemPrompt` in the iOS app; if the app's prompt changes, update here.
//  - maxTokens: clamped to what the app needs; temperature forced to 0;
//    caller tag forced to a server constant.
//  - user message: length-capped (the app already truncates the free text to
//    12000 / 4000 chars before wrapping it in the schema template).
//
// Residual risk: the user message is still client text, so a user can ask a
// different question within these caps — but only with our system prompt,
// <=4096 output tokens, the free monthly session quota and per-session call
// caps. That is bounded, not open-ended.

enum ProgramImportPolicy {
    static let allowedModels: Set<String> = ["sonnet"]
    static let allowedMediaTypes: Set<String> = ["image/jpeg", "image/png", "image/webp"]

    static let structureMaxTokens = 4096
    static let feedbackMaxTokens = 1500

    static let structureCaller = "trainer_program_import"
    static let feedbackCaller = "trainer_feedback_edit"
    static let transcribeCaller = "trainer_program_transcribe"

    /// App sends <=12000 chars of program text + ~6KB schema template.
    static let structureMaxUserMessageChars = 24000
    // App sends <=4000 chars of feedback text + schema template.
    static let feedbackMaxUserMessageChars = 12000
    static let transcribeMaxUserMessageChars = 4000
    static let maxHintChars = 8000

    static let structureSystemPrompt = """
    You extract a personal trainer's training program (a transcript of \
    photos/PDF pages, or pasted text — possibly Italian or English, the \
    athlete is Italian) into strict JSON. The program may mix strength \
    (sets x reps) and conditioning (runs, intervals, drills) sessions. \
    Output ONLY valid JSON: no markdown, no code fences, no commentary \
    before or after it.
    """

    static let feedbackSystemPrompt = """
    You read a personal trainer's short message to their athlete (pasted \
    text, or a WhatsApp screenshot already read into text — possibly \
    Italian or English) and extract every concrete change it asks for as \
    strict JSON. Output ONLY valid JSON: no markdown, no code fences, no \
    commentary before or after it.
    """

    static let transcribeSystemPrompt = """
    You transcribe pages of a personal trainer's training program (photos, \
    scanned sheets, or photographed whiteboards — possibly Italian or \
    English, the athlete is Italian) into faithful plain text. You do not \
    structure, translate or interpret it — transcribe exactly what is \
    written, as accurately as you can. Output plain text only: no markdown, \
    no commentary before or after it.
    """

    enum PolicyError: Error, Equatable {
        case modelNotAllowed(String)
        case userMessageTooLong(max: Int)
        case unsupportedMediaType(String)
        case invalidBase64
        case hintTooLong(max: Int)

        var reason: String {
            switch self {
            case let .modelNotAllowed(model):
                "Model '\(model)' is not allowed on this route."
            case let .userMessageTooLong(max):
                "user_message is too long (max \(max) characters)."
            case let .unsupportedMediaType(type):
                "Unsupported media_type '\(type)'. Use image/jpeg, image/png or image/webp."
            case .invalidBase64:
                "An image is not valid base64."
            case let .hintTooLong(max):
                "A hint text is too long (max \(max) characters)."
            }
        }
    }

    static func validateModel(_ model: String) throws {
        guard allowedModels.contains(model.lowercased()) else {
            throw PolicyError.modelNotAllowed(String(model.prefix(40)))
        }
    }

    static func validateUserMessage(_ message: String, max: Int) throws {
        guard message.count <= max else {
            throw PolicyError.userMessageTooLong(max: max)
        }
    }

    static func clampedMaxTokens(_ requested: Int, cap: Int) -> Int {
        min(cap, Swift.max(1, requested))
    }

    static func validateImage(mediaType: String, base64: String) throws {
        guard allowedMediaTypes.contains(mediaType.lowercased()) else {
            throw PolicyError.unsupportedMediaType(String(mediaType.prefix(40)))
        }
        guard !base64.isEmpty, let data = Data(base64Encoded: base64), !data.isEmpty else {
            throw PolicyError.invalidBase64
        }
    }

    static func validateHints(_ hints: [String?]) throws {
        for hint in hints where (hint?.count ?? 0) > maxHintChars {
            throw PolicyError.hintTooLong(max: maxHintChars)
        }
    }
}
