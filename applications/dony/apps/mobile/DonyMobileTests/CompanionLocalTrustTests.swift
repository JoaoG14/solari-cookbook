import XCTest
@testable import DonyMobile

final class CompanionLocalTrustTests: XCTestCase {
    func testLocalHostValidationAndCaseNormalization() {
        XCTAssertEqual(CompanionLocalTrust(host: "My-Mac.LOCAL", fingerprint: "pin").host, "my-mac.local")
        for host in ["My-Mac.local", "192.168.1.2", "10.0.0.1", "172.16.1.1", "127.0.0.1"] {
            XCTAssertTrue(CompanionLocalTrust.isLocalHost(host), host)
        }
        for host in ["example.com", "example.local.evil.com", "8.8.8.8", "172.32.0.1", "192.168.1.999"] {
            XCTAssertFalse(CompanionLocalTrust.isLocalHost(host), host)
        }
    }

    func testCertificatePinPersistsAndLegacyConnectionsStillDecode() throws {
        let legacy = Data("""
            {"server":"https://example.com","token":"test","deviceId":"phone",
            "desktopId":"desktop","desktopName":"My Mac","accountId":"owner"}
            """.utf8)
        var connection = try JSONDecoder().decode(CompanionConnection.self, from: legacy)
        XCTAssertFalse(connection.isLocal)
        connection.certificateFingerprint = String(repeating: "a", count: 64)
        let restored = try JSONDecoder().decode(CompanionConnection.self, from: JSONEncoder().encode(connection))
        XCTAssertTrue(restored.isLocal)
        XCTAssertEqual(restored.certificateFingerprint, connection.certificateFingerprint)
    }
}
