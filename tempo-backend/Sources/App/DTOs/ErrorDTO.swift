import Vapor

// MARK: - Error DTO
// Per BACKEND_API.md — Error response format.
// { ok: false, error: { code, message, detail?, field? } }

struct ErrorEnvelope: Content {
    var ok: Bool
    var error: ErrorDTO
    var meta: ResponseMeta

    init(code: Int, message: String, detail: String? = nil, field: String? = nil, requestID: String? = nil) {
        self.ok = false
        self.error = ErrorDTO(code: code, message: message, detail: detail, field: field)
        self.meta = ResponseMeta(
            requestID: requestID ?? "req_" + String.randomHex(length: 12),
            timestamp: Date()
        )
    }
}

struct ErrorDTO: Content {
    let code: Int
    let message: String
    let detail: String?
    let field: String?

    init(code: Int, message: String, detail: String? = nil, field: String? = nil) {
        self.code = code
        self.message = message
        self.detail = detail
        self.field = field
    }
}
