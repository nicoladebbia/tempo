@testable import App
import Crypto
import Foundation
import Testing
import Vapor

// MARK: - WHOOP decoding (regression: the app-wide decoder cannot read DTOs that declare their own snake_case keys)

@Suite("WHOOP decoding")
struct WhoopDecodingTests {
    /// WHOOP's own v1 sample (developer.whoop.com, 2026-11-20).
    private let v1 = #"{"records":[{"id":1043,"user_id":9012,"created_at":"2022-04-24T11:25:44.774Z","updated_at":"2022-04-24T14:25:44.774Z","start":"2022-04-24T02:25:44.774Z","end":"2022-04-24T10:25:44.774Z","timezone_offset":"-05:00","sport_id":1,"score_state":"SCORED","score":{"strain":8.2463,"average_heart_rate":123,"max_heart_rate":146,"kilojoule":1569.34,"percent_recorded":100,"distance_meter":1772.77,"altitude_gain_meter":46.64,"altitude_change_meter":-0.781,"zone_duration":{"zone_zero_milli":300000,"zone_one_milli":300000,"zone_two_milli":300000,"zone_three_milli":300000,"zone_four_milli":300000,"zone_five_milli":300000}}}],"next_token":null}"#

    /// WHOOP's own v2 shape.
    private let v2 = #"{"records":[{"id":"ecfc6a15-4661-442f-a9a4-f160dd7afae8","v1_id":1043,"user_id":9012,"created_at":"2022-04-24T11:25:44.774Z","updated_at":"2022-04-24T14:25:44.774Z","start":"2022-04-24T02:25:44.774Z","end":"2022-04-24T10:25:44.774Z","timezone_offset":"-05:00","sport_name":"running","score_state":"SCORED","score":{"strain":8.2463,"average_heart_rate":123,"max_heart_rate":146,"kilojoule":1569.34,"percent_recorded":100,"distance_meter":1772.77,"altitude_gain_meter":46.64,"altitude_change_meter":-0.781,"zone_durations":{"zone_zero_milli":300000,"zone_one_milli":300000,"zone_two_milli":300000,"zone_three_milli":300000,"zone_four_milli":300000,"zone_five_milli":300000}}}],"next_token":null}"#

    @Test func v1WorkoutResponseDecodesThroughWhoopJSON() throws {
        let r = try WhoopJSON.decode(WhoopAPIWorkoutResponse.self, from: Data(v1.utf8))
        #expect(r.records.count == 1 && r.records[0].id == 1043 && r.records[0].userId == 9012)
        #expect(r.records[0].score?.kilojoule == 1569.34)
    }

    @Test func theAppWideDecoderStillCannotReadThoseDTOs_whichIsWhyWhoopJSONExists() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)
        var buffer = ByteBufferAllocator().buffer(capacity: v1.utf8.count)
        buffer.writeString(v1)
        let decoder = try ContentConfiguration.global.requireDecoder(for: .json)
        #expect(throws: DecodingError.self) { try decoder.decode(WhoopAPIWorkoutResponse.self, from: buffer, headers: [:]) }
    }

    @Test func v2WorkoutDecodesAndBecomesACoachSession() throws {
        let r = try WhoopJSON.decode(WhoopV2WorkoutResponse.self, from: Data(v2.utf8))
        let record = try #require(r.records.first)
        #expect(record.id == "ecfc6a15-4661-442f-a9a4-f160dd7afae8" && record.v1Id == 1043 && record.sportName == "running")
        let s = try #require(CoachSessionRules.session(from: record))
        #expect(s.id == record.id && s.durationMinutes == 480 && s.kilojoules == 1569.34)
    }

    @Test func webhookEventsDecodeWithNumericAndUUIDIdsThroughTheAppDecoder() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        try await configure(app)
        let decoder = try ContentConfiguration.global.requireDecoder(for: .json)
        func event(_ json: String) throws -> WhoopWebhookEvent {
            var b = ByteBufferAllocator().buffer(capacity: json.utf8.count)
            b.writeString(json)
            return try decoder.decode(WhoopWebhookEvent.self, from: b, headers: [:])
        }
        let v1 = try event(#"{"user_id":456,"id":10235,"type":"workout.updated","trace_id":"d3709ee7-104e-4f70-a928-2932964b017b"}"#)
        #expect(v1.id == "10235" && v1.userId == 456 && v1.type == "workout.updated" && v1.traceId.hasPrefix("d3709ee7"))
        let v2 = try event(#"{"user_id":456,"id":"ecfc6a15-4661-442f-a9a4-f160dd7afae8","type":"workout.updated","trace_id":"t-1"}"#)
        #expect(v2.id == "ecfc6a15-4661-442f-a9a4-f160dd7afae8")
    }
}

// MARK: - Webhook signature (WHOOP docs: base64(HMAC-SHA256(timestamp_ms + raw_body, client_secret)))

@Suite("WHOOP webhook signature", .serialized)
struct WhoopWebhookSignatureTests {
    private static let secret = "unit-test-whoop-secret"
    private let body = #"{"user_id":999999991,"id":"ecfc6a15-4661-442f-a9a4-f160dd7afae8","type":"workout.updated","trace_id":"trace-sig-test"}"#

    private func post(_ app: Application, signature: String?, timestamp: String?, bodyText: String? = nil) async throws -> HTTPStatus {
        var status = HTTPStatus.ok
        try await app.test(.POST, "v1/webhooks/whoop", beforeRequest: { req in
            req.headers.contentType = .json
            if let signature { req.headers.replaceOrAdd(name: "X-WHOOP-Signature", value: signature) }
            if let timestamp { req.headers.replaceOrAdd(name: "X-WHOOP-Signature-Timestamp", value: timestamp) }
            req.body = ByteBuffer(string: bodyText ?? body)
        }, afterResponse: { res async throws in status = res.status })
        return status
    }

    private func withApp(_ run: (Application) async throws -> Void) async throws {
        setenv("WHOOP_WEBHOOK_SECRET", Self.secret, 1)
        defer { unsetenv("WHOOP_WEBHOOK_SECRET") }
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await run(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func nowMs(offsetSeconds: Double = 0) -> String { String(Int64((Date().timeIntervalSince1970 + offsetSeconds) * 1000)) }

    @Test func aCorrectlySignedDeliveryIsAccepted() async throws {
        try await withApp { app in
            let ts = nowMs()
            let sig = WhoopWebhookMiddleware.expectedSignature(timestamp: ts, body: body, secret: Self.secret)
            let status = try await post(app, signature: sig, timestamp: ts)
            #expect(status == .ok) // unknown WHOOP user: acknowledged, ignored
        }
    }

    @Test func signatureFormulaMatchesWhoopsDocumentation() {
        // timestamp + body, no separator, HMAC-SHA256, base64.
        let mac = HMAC<SHA256>.authenticationCode(for: Data(("1700000000000" + "{}").utf8), using: SymmetricKey(data: Data("k".utf8)))
        #expect(WhoopWebhookMiddleware.expectedSignature(timestamp: "1700000000000", body: "{}", secret: "k") == Data(mac).base64EncodedString())
    }

    @Test func wrongSignatureOldHexFormatAndTamperedBodyAreRejected() async throws {
        try await withApp { app in
            let ts = nowMs()
            let good = WhoopWebhookMiddleware.expectedSignature(timestamp: ts, body: body, secret: Self.secret)
            let wrong = try await post(app, signature: "AAAA", timestamp: ts)
            let hexOldFormat = HMAC<SHA256>.authenticationCode(for: Data("\(ts).\(body)".utf8), using: SymmetricKey(data: Data(Self.secret.utf8)))
                .map { String(format: "%02x", $0) }.joined()
            let oldFormat = try await post(app, signature: hexOldFormat, timestamp: ts)
            let tampered = try await post(app, signature: good, timestamp: ts, bodyText: body.replacingOccurrences(of: "999999991", with: "1"))
            #expect(wrong == .unauthorized && oldFormat == .unauthorized && tampered == .unauthorized)
        }
    }

    @Test func staleOrMissingHeadersAreRejected() async throws {
        try await withApp { app in
            let stale = nowMs(offsetSeconds: -600)
            let sig = WhoopWebhookMiddleware.expectedSignature(timestamp: stale, body: body, secret: Self.secret)
            let old = try await post(app, signature: sig, timestamp: stale)
            let future = nowMs(offsetSeconds: 600)
            let ahead = try await post(app, signature: WhoopWebhookMiddleware.expectedSignature(timestamp: future, body: body, secret: Self.secret), timestamp: future)
            let noSignature = try await post(app, signature: nil, timestamp: nowMs())
            let noTimestamp = try await post(app, signature: "x", timestamp: nil)
            #expect(old == .unauthorized && ahead == .unauthorized, "10 minutes old or 10 minutes ahead")
            #expect(noSignature == .badRequest && noTimestamp == .badRequest)
        }
    }
}
