import Vapor

// MARK: - TempoErrorMiddleware
//
// Custom replacement for Vapor's default `ErrorMiddleware` that preserves the
// `identifier` field on `Abort`. iOS uses the identifier to distinguish
// "subscription_required" from "ai_consent_required" without parsing free-text
// `reason` strings.
//
// Wire format:
//   {
//     "error": true,
//     "reason": "Pro subscription required for AI features.",
//     "code": "subscription_required"   // <- the identifier
//   }
//
// Per INTELLIGENCE_REMEDIATION_PLAN.md §4.

struct TempoErrorMiddleware: AsyncMiddleware {
    let environment: Environment

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return errorResponse(for: error, on: request)
        }
    }

    private func errorResponse(for error: Error, on request: Request) -> Response {
        let status: HTTPResponseStatus
        let reason: String
        let identifier: String?
        let headers: HTTPHeaders

        switch error {
        case let abort as AbortError:
            status = abort.status
            reason = abort.reason
            headers = abort.headers
            // AbortError exposes identifier via Abort, but the protocol surface
            // only guarantees status/reason/headers. Cast to Abort if available.
            identifier = (error as? Abort)?.identifier
        default:
            status = .internalServerError
            reason = environment.isRelease
                ? "Something went wrong."
                : String(describing: error)
            headers = [:]
            identifier = nil
        }

        if status.code >= 500 {
            request.logger.report(error: error)
        }

        let body = TempoErrorBody(error: true, reason: reason, code: identifier)
        let response = Response(status: status, headers: headers)
        do {
            try response.content.encode(body)
        } catch {
            response.body = .init(string: #"{"error":true,"reason":"Encoding failed"}"#)
        }
        return response
    }
}

private struct TempoErrorBody: Content {
    let error: Bool
    let reason: String
    let code: String?
}
