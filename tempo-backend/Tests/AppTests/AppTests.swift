@testable import App
import Testing
import XCTVapor

struct AppTests {
    @Test func healthEndpoint() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try await configure(app)

        try await app.test(.GET, "health") { res async in
            #expect(res.status == .ok)
        }
        // RediStack's 10 ms default made busy moments 500 at random.
        #expect(app.redis.configuration?.pool.connectionRetryTimeout == .seconds(1))
    }
}
