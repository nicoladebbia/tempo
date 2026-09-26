@testable import App
import Foundation
import Testing
import VaporAPNS

// MARK: - APNs routing

//
// Xcode builds register sandbox tokens for `app.tempo.Tempo.dev`; App Store
// builds production tokens for `app.tempo.Tempo`. Pushing through the wrong
// environment/topic is rejected — and the rejection deletes the token.

@Suite("APNs routing")
struct APNsRoutingTests {
    private func device(bundleID: String?, environment: String?) -> DeviceToken {
        DeviceToken(
            userID: "u1",
            token: String(repeating: "a", count: 64),
            deviceID: "d1",
            bundleID: bundleID,
            apnsEnvironment: environment
        )
    }

    @Test func xcodeBuildGoesThroughSandboxWithItsOwnBundle() {
        let route = APNsService.route(for: device(bundleID: "app.tempo.Tempo.dev", environment: "sandbox"))
        #expect(route.container == .development)
        #expect(route.topic == "app.tempo.Tempo.dev")
    }

    @Test func appStoreBuildGoesThroughProduction() {
        let route = APNsService.route(for: device(bundleID: "app.tempo.Tempo", environment: "production"))
        #expect(route.container == .production)
        #expect(route.topic == "app.tempo.Tempo")
    }

    @Test func oldRegistrationsFallBackToProductionAndTheReleaseBundle() {
        let route = APNsService.route(for: device(bundleID: nil, environment: nil))
        #expect(route.container == .production)
        #expect(route.topic == (ProcessInfo.processInfo.environment["APNS_TOPIC"] ?? "app.tempo.Tempo"))
    }

    @Test func registerBodyDecodesRoutingAndStaysOptional() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let new = try decoder.decode(DeviceTokenRegisterDTO.self, from: Data("""
        {"token":"ab","device_id":"d1","device_name":"iPhone","app_version":"1.0.0","bundle_id":"app.tempo.Tempo.dev","apns_environment":"sandbox"}
        """.utf8))
        #expect(new.bundleID == "app.tempo.Tempo.dev")
        #expect(new.apnsEnvironment == "sandbox")
        let old = try decoder.decode(DeviceTokenRegisterDTO.self, from: Data("""
        {"token":"ab","device_id":"d1","device_name":null,"app_version":null}
        """.utf8))
        #expect(old.bundleID == nil)
        #expect(old.apnsEnvironment == nil)
    }
}
