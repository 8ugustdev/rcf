import XCTest
@testable import RCF

/// Phase 1 smoke tests: theme persistence + maskers + formatters.
@MainActor
final class SmokeTests: XCTestCase {
    func testThemePreferenceDefaultsToInkDark() {
        let suite = UserDefaults(suiteName: "SmokeTestsTheme")!
        suite.removePersistentDomain(forName: "SmokeTestsTheme")
        let theme = ThemeManager(defaults: suite)
        XCTAssertEqual(theme.preference, .dark)
        XCTAssertEqual(theme.preference.colorScheme, .dark)
    }

    func testThemePreferencePersists() {
        let suite = UserDefaults(suiteName: "SmokeTestsTheme2")!
        suite.removePersistentDomain(forName: "SmokeTestsTheme2")
        let theme = ThemeManager(defaults: suite)
        theme.preference = .dark
        let reloaded = ThemeManager(defaults: suite)
        XCTAssertEqual(reloaded.preference, .dark)
        XCTAssertEqual(reloaded.preference.colorScheme, .dark)
    }

    func testLegacyRawValuesMigrateToDark() {
        let suite = UserDefaults(suiteName: "SmokeTestsThemeLegacy")!
        suite.removePersistentDomain(forName: "SmokeTestsThemeLegacy")
        suite.set("inkDark", forKey: ThemeManager.preferenceKey)
        let theme = ThemeManager(defaults: suite)
        XCTAssertEqual(theme.preference, .dark)
    }

    func testDefaultThemeIsInkDarkFreshInstall() {
        let suite = UserDefaults(suiteName: "SmokeTestsThemeFresh")!
        suite.removePersistentDomain(forName: "SmokeTestsThemeFresh")
        XCTAssertEqual(ThemeManager(defaults: suite).preference, .dark)
    }

    func testTokenMasking() {
        XCTAssertEqual(Masking.token("abcdefghijklmnop"), "abcd••••mnop")
        XCTAssertEqual(Masking.token("short"), "•••••")
    }

    func testEmailMasking() {
        let masked = Masking.email("john.doe@example.com")
        XCTAssertTrue(masked.hasPrefix("j"))
        XCTAssertTrue(masked.contains("@"))
        XCTAssertTrue(masked.hasSuffix(".com"))
    }

    func testDomainMasking() {
        XCTAssertEqual(Masking.domain("site.example.com"), "s•••.e•••.com")
        XCTAssertEqual(Masking.domain("single"), "single")
    }

    func testBytesFormatting() {
        XCTAssertTrue(Formatters.bytes(1536).contains("KB"))
    }
}

/// Dashboard quick-action destinations hash per action+zone so navigation stays distinct.
@MainActor
final class WorkspaceShellTests: XCTestCase {
    static let zoneJSON = """
    {"id":"z1","name":"example.com","status":"active","paused":false,"type":"full",
     "development_mode":0,"name_servers":["ns1.cloudflare.com"],
     "modified_on":null,"created_on":null,"activated_on":null,
     "plan":{"id":"p","name":"Free","price":0,"currency":"USD","frequency":"","is_subscribed":false},
     "account":{"id":"a1","name":"Account"}}
    """

    func testRecentsMRUOrdering() throws {
        let suite = UserDefaults(suiteName: "WorkspaceRecents")!
        suite.removePersistentDomain(forName: "WorkspaceRecents")
        DashboardRecents.record("a", defaults: suite)
        DashboardRecents.record("b", defaults: suite)
        DashboardRecents.record("a", defaults: suite)
        XCTAssertEqual(DashboardRecents.ids(defaults: suite).first, "a")
        XCTAssertEqual(DashboardRecents.ids(defaults: suite).count, 2)
    }

    func testLastZonePersistsAndRecentsUpdated() throws {
        let suite = UserDefaults(suiteName: "WorkspaceLastZone")!
        suite.removePersistentDomain(forName: "WorkspaceLastZone")
        suite.set("z1", forKey: AppShell.lastZoneKey)
        XCTAssertEqual(suite.string(forKey: AppShell.lastZoneKey), "z1")
        DashboardRecents.record("z1", defaults: suite)
        XCTAssertTrue(DashboardRecents.ids(defaults: suite).contains("z1"))
    }
}
