import XCTest
@testable import RCF

/// AppLockManager state machine with injected auth (no system prompt in tests).
@MainActor
final class AppLockTests: XCTestCase {
    private func makeLock(enabled: Bool, result: Bool) -> (AppLockManager, UserDefaults) {
        let suite = UserDefaults(suiteName: "locktests.\(UUID().uuidString)")!
        suite.set(enabled, forKey: AppLockManager.enabledKey)
        let lock = AppLockManager(defaults: suite)
        lock.biometricsAvailable = true
        lock.authenticate = { _ in result }
        return (lock, suite)
    }

    func testDisabledLockNeverEngages() async {
        let (lock, _) = makeLock(enabled: false, result: true)
        lock.scenePhaseChanged(.background)
        XCTAssertFalse(lock.isLocked)
    }

    func testBackgroundLocksWhenEnabled() async {
        let (lock, _) = makeLock(enabled: true, result: true)
        lock.scenePhaseChanged(.background)
        XCTAssertTrue(lock.isLocked)
    }

    func testActiveUnlocksOnSuccess() async {
        let (lock, _) = makeLock(enabled: true, result: true)
        lock.scenePhaseChanged(.background)
        lock.scenePhaseChanged(.active)
        // unlock task ran via scenePhaseChanged; wait briefly
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(lock.isLocked)
    }

    func testFailedAuthStaysLocked() async {
        let (lock, _) = makeLock(enabled: true, result: false)
        lock.scenePhaseChanged(.background)
        await lock.unlock()
        XCTAssertTrue(lock.isLocked)
    }

    func testEnablingLocksImmediately() {
        let suite = UserDefaults(suiteName: "locktests.\(UUID().uuidString)")!
        suite.set(false, forKey: AppLockManager.enabledKey)
        let lock = AppLockManager(defaults: suite)
        lock.biometricsAvailable = true
        lock.authenticate = { _ in true }
        lock.isEnabled = true
        XCTAssertTrue(lock.isLocked)
    }
}

/// AuthViewModel gate: onboarding flag → login; sign-out resets.
@MainActor
final class AuthGateTests: XCTestCase {
    func testFreshInstallShowsOnboardingThenLogin() {
        let suite = UserDefaults(suiteName: "authgate.\(UUID().uuidString)")!
        let profiles = ProfileStore(
            keychain: KeychainStore(service: "authgate.\(UUID().uuidString)"),
            defaults: suite
        )
        let auth = AuthViewModel(profiles: profiles, defaults: suite)
        auth.completeOnboarding(defaults: suite)
        XCTAssertEqual(auth.phase, .login)
    }
}
