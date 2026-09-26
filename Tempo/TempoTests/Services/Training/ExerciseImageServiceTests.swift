//
// ExerciseImageServiceTests.swift
// Tempo
//
// Covers the 404 -> generate -> re-fetch -> cache flow with a mocked
// APIClient/URLProtocol (never a real network call — see MockURLProtocol),
// plus the signed-out skip, session-memoized-failure and
// at-most-one-in-flight-per-slug contracts.
//

@testable import Tempo
import XCTest

// MARK: - ExerciseImageServiceTests

@MainActor
final class ExerciseImageServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        MockURLProtocol.reset()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.reset()
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    private func makeService(isSignedIn: Bool = true) -> ExerciseImageService {
        let session = MockURLProtocol.makeSession()
        let apiClient = APIClient(session: session)
        return ExerciseImageService(
            apiClient: apiClient,
            isSignedIn: { isSignedIn },
            session: session,
            cacheDirectoryOverride: tempDir
        )
    }

    private func makeExercise(name: String = "Barbell Back Squat") -> Exercise {
        Exercise(
            name: name,
            muscleGroup: .quads,
            equipment: .barbell,
            movementPattern: .squat,
            isCompound: true,
            instructions: "Squat down, stand back up."
        )
    }

    // MARK: - Disk cache short-circuit

    func testReturnsDiskCachedBytesWithoutAnyNetworkCall() async throws {
        let service = makeService()
        let exercise = makeExercise()
        let slug = ExerciseImageSlug.make(from: exercise.name)
        let cacheFile = tempDir.appendingPathComponent("\(slug).jpg")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fixture = Data([0xFF, 0xD8, 0xFF])
        try fixture.write(to: cacheFile)

        MockURLProtocol.setHandler { _ in
            XCTFail("Should not hit the network when the disk cache already has this slug")
            return .init(statusCode: 500)
        }

        let result = await service.imageData(for: exercise)
        XCTAssertEqual(result, fixture)
    }

    // MARK: - 404 -> generate -> re-fetch

    func test404ThenGenerateThenRefetch_returnsGeneratedBytesAndCachesToDisk() async throws {
        let service = makeService()
        let exercise = makeExercise()
        let generatedBytes = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])
        let getCallCount = LockedCounter()

        MockURLProtocol.setHandler { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path == "/v1/exercise-images" {
                let body = #"{"ok":true,"data":{"slug":"barbell-back-squat","url":"https://x/y","status":"ready"}}"#
                return .init(statusCode: 200, data: Data(body.utf8), headers: ["Content-Type": "application/json"])
            }
            if request.httpMethod == "GET", path.hasPrefix("/v1/exercise-images/") {
                if getCallCount.incrementAndGet() == 1 {
                    return .init(statusCode: 404)
                }
                return .init(statusCode: 200, data: generatedBytes, headers: ["Content-Type": "image/jpeg"])
            }
            XCTFail("Unexpected request: \(request.httpMethod ?? "?") \(path)")
            return .init(statusCode: 500)
        }

        let result = await service.imageData(for: exercise)
        XCTAssertEqual(result, generatedBytes)
        XCTAssertEqual(getCallCount.value, 2, "expected 404 then a re-fetch after generation")

        let slug = ExerciseImageSlug.make(from: exercise.name)
        let cachedOnDisk = try Data(contentsOf: tempDir.appendingPathComponent("\(slug).jpg"))
        XCTAssertEqual(cachedOnDisk, generatedBytes)
    }

    // MARK: - Signed out — never calls generate

    func testSignedOut_neverCallsGenerateAndReturnsNil() async {
        let service = makeService(isSignedIn: false)
        let exercise = makeExercise()
        let postCallCount = LockedCounter()

        MockURLProtocol.setHandler { request in
            if request.httpMethod == "POST" {
                postCallCount.increment()
                return .init(statusCode: 200, data: Data(#"{"ok":true,"data":{}}"#.utf8))
            }
            return .init(statusCode: 404)
        }

        let result = await service.imageData(for: exercise)
        XCTAssertNil(result)
        XCTAssertEqual(postCallCount.value, 0, "signed-out path must never call POST /v1/exercise-images")
    }

    // MARK: - Session-memoized failure — no hammering

    /// Uses 503, not 429: APIClient.isRetryable treats BOTH as retryable, but
    /// .rateLimited retries at `Retry-After ?? 60s` per attempt (x3 = up to
    /// 180s wall-clock for a single call with no Retry-After header — that's
    /// real, accepted APIClient behavior, not something to fight in a unit
    /// test). ExerciseImageService's generate `catch` doesn't branch on
    /// status code at all (see fetchOrGenerate), so 503's ~7s exponential
    /// backoff (1s+2s+4s) exercises the exact same memoization code path
    /// without the 429 case's 3-minute tax on every test run.
    func test503OnGenerate_memoizesFailureForSession_secondCallHitsNoNetwork() async {
        let service = makeService()
        let exercise = makeExercise()
        let requestCount = LockedCounter()

        MockURLProtocol.setHandler { request in
            requestCount.increment()
            if request.httpMethod == "POST" {
                return .init(statusCode: 503)
            }
            return .init(statusCode: 404)
        }

        let first = await service.imageData(for: exercise)
        XCTAssertNil(first)
        let countAfterFirst = requestCount.value

        let second = await service.imageData(for: exercise)
        XCTAssertNil(second)
        XCTAssertEqual(requestCount.value, countAfterFirst, "second call must not hit the network again this session")
    }

    // MARK: - At most one in-flight request per slug

    func testAtMostOneInFlightRequestPerSlug() async {
        let service = makeService()
        let generatedBytes = Data([0xAA, 0xBB])
        let postCallCount = LockedCounter()
        let getCallCount = LockedCounter()

        MockURLProtocol.setHandler { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                postCallCount.increment()
                // Simulate the real ~10-30s generation latency with a short
                // sleep so both concurrent callers are genuinely racing.
                Thread.sleep(forTimeInterval: 0.05)
                let body = #"{"ok":true,"data":{"slug":"barbell-back-squat","url":"https://x/y","status":"ready"}}"#
                return .init(statusCode: 200, data: Data(body.utf8), headers: ["Content-Type": "application/json"])
            }
            if getCallCount.incrementAndGet() == 1 {
                return .init(statusCode: 404)
            }
            return .init(statusCode: 200, data: generatedBytes, headers: ["Content-Type": "image/jpeg"])
        }

        // Sendable ExerciseImageInput, not a live Exercise — sending a
        // non-Sendable SwiftData model into two concurrent async-let child
        // tasks from the same call site is itself a Swift 6 region-isolation
        // error, unrelated to what this test is verifying (the dedupe path).
        let input = ExerciseImageInput(
            name: "Barbell Back Squat", equipmentRaw: "barbell", muscleGroupRaw: "quads",
            movementPatternRaw: "squat", instructions: nil
        )
        async let first = service.imageData(for: input)
        async let second = service.imageData(for: input)
        let (resultA, resultB) = await (first, second)

        XCTAssertEqual(resultA, generatedBytes)
        XCTAssertEqual(resultB, generatedBytes)
        XCTAssertEqual(postCallCount.value, 1, "two concurrent callers for the same slug must generate only once")
    }
}

// MARK: - LockedCounter

/// Thread-safe counter for assertions from the mock handler closure, which
/// MockURLProtocol may invoke off the main actor.
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
    }

    /// Atomic increment-then-read — avoids the increment/read race a
    /// separate `.increment()` + `.value` pair would have under real
    /// concurrent access.
    @discardableResult
    func incrementAndGet() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
}
