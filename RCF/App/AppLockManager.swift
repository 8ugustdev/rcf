import Foundation
import LocalAuthentication
import SwiftUI

/// Biometric/passcode app lock: engage on background→foreground when enabled.
@MainActor
@Observable
final class AppLockManager {
    static let enabledKey = "rcf.app_lock.enabled"

    private let defaults: UserDefaults

    /// Lock engaged — overlay shown until authentication succeeds.
    private(set) var isLocked = false
    /// Whether biometric/passcode auth is available on this device.
    /// Internal setter for unit tests to bypass LAContext.
    var biometricsAvailable = false
    /// Set while the system auth prompt is up (prevents re-prompt loops).
    private(set) var isAuthenticating = false
    /// Injectable prompt for unit tests.
    var authenticate: @MainActor (String) async -> Bool = { _ in false }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authenticate = { reason in
            let context = LAContext()
            context.localizedCancelTitle = "Cancel"
            do {
                return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            } catch {
                return false
            }
        }
        refreshAvailability()
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if newValue { lock() }
        }
    }

    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        biometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Lock now (manual lock action or setting enabled).
    func lock() {
        guard isEnabled, biometricsAvailable else { return }
        isLocked = true
    }

    /// Called on scenePhase transitions.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lock()
        case .active:
            if isLocked, !isAuthenticating {
                Task { await unlock() }
            }
        default:
            break
        }
    }

    /// Runs the biometric/passcode prompt.
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ok = await authenticate("Unlock RCF")
        if ok {
            isLocked = false
        }
    }
}

/// Full-screen lock cover shown while locked.
struct AppLockOverlay: View {
    @Environment(AppLockManager.self) private var lock

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.cfAccent)
            Text("RCF is locked")
                .font(.title3.bold())
                .foregroundStyle(.cfText)
            Button("Unlock") {
                Task { await lock.unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.cfBackground)
    }
}
