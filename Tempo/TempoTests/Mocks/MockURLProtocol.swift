//
// MockURLProtocol.swift
// Tempo
//
// Generic URLProtocol stub for network tests — intercepts every request
// regardless of host/scheme, so it works for both a raw URLSession.data(from:)
// call and requests made through APIClient (which is handed the same
// mock-backed URLSession). Callers supply a handler closure that inspects
// the URLRequest (path, method) and returns a canned status/body.
//

import Foundation

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let statusCode: Int
        let data: Data
        let headers: [String: String]

        init(statusCode: Int, data: Data = Data(), headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.data = data
            self.headers = headers
        }
    }

    private static let lock = NSLock()
    // Manually synchronized via `lock` (every read/write below is inside a
    // lock/unlock pair) — `nonisolated(unsafe)` tells Swift 6 strict
    // concurrency to trust that instead of flagging global mutable state.
    private nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Stub)?
    private nonisolated(unsafe) static var requestLog: [URLRequest] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handler = nil
        requestLog = []
    }

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) -> Stub) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requestLog
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - URLProtocol

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requestLog.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        let stub = handler(request)
        guard let response = HTTPURLResponse(
            url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers
        )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
