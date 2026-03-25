import Vapor

// MARK: - Security Headers Middleware
// Per VAPOR_PROJECT_STRUCTURE.md — Adds security headers to every response.

struct SecurityHeadersMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        var response = try await next.respond(to: request)
        response.headers.replaceOrAdd(
            name: .strictTransportSecurity,
            value: "max-age=63072000; includeSubDomains; preload"
        )
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        response.headers.replaceOrAdd(name: "X-Frame-Options", value: "DENY")
        response.headers.replaceOrAdd(
            name: "Referrer-Policy",
            value: "strict-origin-when-cross-origin"
        )
        response.headers.replaceOrAdd(
            name: "Content-Security-Policy",
            value: "default-src 'none'"
        )
        response.headers.replaceOrAdd(
            name: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()"
        )
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }
}
