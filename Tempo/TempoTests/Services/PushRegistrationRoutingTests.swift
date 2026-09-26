//
// PushRegistrationRoutingTests.swift
// Tempo
//
// The server pushes each token through the APNs environment + topic the app
// reports here; a mismatch makes APNs reject (and the server delete) it.
//

@testable import Tempo
import XCTest

final class PushRegistrationRoutingTests: XCTestCase {
    private func profile(apsEnvironment: String?) -> Data {
        let entitlement = apsEnvironment.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Name</key><string>Tempo Dev</string>
        <key>Entitlements</key><dict>\(entitlement)<key>application-identifier</key><string>942QL2V6SV.app.tempo.Tempo.dev</string></dict>
        </dict></plist>
        """
        // Real profiles wrap the plist in binary CMS bytes.
        return Data([0x30, 0x82, 0x4E, 0x00, 0xFF]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x00])
    }

    func testDevelopmentProfileMeansSandbox() {
        XCTAssertEqual(DeviceTokenRegisterBody.apnsEnvironment(inProvisioningProfile: profile(apsEnvironment: "development")), "sandbox")
    }

    func testProductionProfileOrNoneMeansProduction() {
        XCTAssertEqual(DeviceTokenRegisterBody.apnsEnvironment(inProvisioningProfile: profile(apsEnvironment: "production")), "production")
        XCTAssertEqual(DeviceTokenRegisterBody.apnsEnvironment(inProvisioningProfile: profile(apsEnvironment: nil)), "production")
        XCTAssertEqual(DeviceTokenRegisterBody.apnsEnvironment(inProvisioningProfile: Data("junk".utf8)), "production")
    }

    func testRegisterBodySendsRoutingInSnakeCase() throws {
        let body = DeviceTokenRegisterBody(
            token: "ab", deviceID: "d1", deviceName: nil, appVersion: "1.0.0",
            bundleID: "app.tempo.Tempo.dev", apnsEnvironment: "sandbox"
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(json["bundle_id"] as? String, "app.tempo.Tempo.dev")
        XCTAssertEqual(json["apns_environment"] as? String, "sandbox")
    }
}
