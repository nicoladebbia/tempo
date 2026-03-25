@testable import App
import XCTVapor
import Testing

struct AppTests {
    @Test func healthEndpoint() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try await configure(app)

        try await app.test(.GET, "health") { res async in
            #expect(res.status == .ok)
        }
    }
}
