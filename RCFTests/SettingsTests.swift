import XCTest
@testable import RCF

final class SettingsTests: XCTestCase {
    func testMembersEndpoint() {
        let request = CloudflareEndpoint.accountMembers(accountId: "acc", page: 2)
        XCTAssertEqual(request.path, "/accounts/acc/members")
        XCTAssertTrue(request.query.contains { $0.name == "page" && $0.value == "2" })
    }

    func testMemberFixtureDecode() throws {
        let json = """
        {"id":"m1","status":"accepted","user":{"id":"u1","email":"owner@example.com","first_name":"Ada","last_name":"Lovelace"},"roles":[{"id":"r1","name":"Administrator","description":"All access"}]}
        """
        let member = try JSONDecoder().decode(AccountMember.self, from: Data(json.utf8))
        XCTAssertEqual(member.user.firstName, "Ada")
        XCTAssertEqual(member.roles.first?.name, "Administrator")
    }

    func testPrivacyMaskingDefaultsOnAndCanDisable() {
        let key = "rcf.privacy.maskSensitive"
        let prior = UserDefaults.standard.object(forKey: key)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertNotEqual(Masking.email("owner@example.com"), "owner@example.com")
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertEqual(Masking.email("owner@example.com"), "owner@example.com")
    }
}

/// always_use_https arrives as string "on"/"off" from the API, not bool.
final class SSLSettingsTests: XCTestCase {
    func testAlwaysHTTPSAcceptsStringOnAndBool() {
        XCTAssertTrue(SSLViewModel.alwaysHTTPSIsOn(.string("on")))
        XCTAssertTrue(SSLViewModel.alwaysHTTPSIsOn(.bool(true)))
        XCTAssertFalse(SSLViewModel.alwaysHTTPSIsOn(.string("off")))
        XCTAssertFalse(SSLViewModel.alwaysHTTPSIsOn(.bool(false)))
        XCTAssertFalse(SSLViewModel.alwaysHTTPSIsOn(nil))
    }
}
