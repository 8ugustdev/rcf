import XCTest
@testable import RCF

/// Keychain round-trip + ProfileStore persistence (simulator keychain available).
@MainActor
final class KeychainStoreTests: XCTestCase {
    private var keychain: KeychainStore!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        keychain = KeychainStore(service: "rcf.tests.\(UUID().uuidString)")
        let suiteName = "rcf.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    func testKeychainRoundTrip() throws {
        let data = Data("secret-profiles".utf8)
        try keychain.write(data, account: "list")
        let read = try keychain.read(account: "list")
        XCTAssertEqual(read, data)

        try keychain.write(Data("updated".utf8), account: "list")
        XCTAssertEqual(try keychain.read(account: "list"), Data("updated".utf8))

        try keychain.delete(account: "list")
        XCTAssertNil(try keychain.read(account: "list"))
    }

    func testProfilesPersistAcrossStoreReInit() throws {
        let store = ProfileStore(keychain: keychain, defaults: defaults)
        try store.add(Profile(label: "Work", auth: .token("tok-1111")))
        try store.add(Profile(label: "Personal", auth: .globalKey(email: "me@example.com", key: "gk")))

        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertEqual(store.activeProfile?.label, "Personal")

        // Re-init simulates app relaunch: same keychain + defaults.
        let reloaded = ProfileStore(keychain: keychain, defaults: defaults)
        XCTAssertEqual(reloaded.profiles.map(\.label), ["Work", "Personal"])
        XCTAssertEqual(reloaded.activeProfile?.label, "Personal")

        try reloaded.setActive(id: reloaded.profiles[0].id)
        let again = ProfileStore(keychain: keychain, defaults: defaults)
        XCTAssertEqual(again.activeProfile?.label, "Work")
    }

    func testRemoveActiveFallsBackToFirst() throws {
        let store = ProfileStore(keychain: keychain, defaults: defaults)
        let first = try store.add(Profile(label: "A", auth: .token("t1")))
        _ = try store.add(Profile(label: "B", auth: .token("t2")))
        try store.remove(id: first.id)
        XCTAssertEqual(store.profiles.map(\.label), ["B"])
        XCTAssertEqual(store.activeProfile?.label, "B")
    }

    func testAuthConfigCodableRoundTrip() throws {
        let tokenConfig = AuthConfig.token("abcdefgh1234")
        let keyConfig = AuthConfig.globalKey(email: "a@b.c", key: "k")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(AuthConfig.self, from: try encoder.encode(tokenConfig)), tokenConfig)
        XCTAssertEqual(try decoder.decode(AuthConfig.self, from: try encoder.encode(keyConfig)), keyConfig)
        XCTAssertEqual(tokenConfig.maskedDescription, "Token abcd••••1234")
        XCTAssertEqual(keyConfig.maskedDescription, "Global key (a•••@b•••.c)")
    }
}
