import Foundation
import SwiftUI

/// Root auth state machine: loading → onboarding? → login ⇄ authenticated.
@MainActor
@Observable
final class AuthViewModel {
    enum Phase: Equatable {
        case loading
        case onboarding
        case login
        case authenticated
    }

    static let onboardingKey = "rcf.onboarding.done"

    private(set) var phase: Phase = .loading
    private(set) var session: Session?
    private(set) var loginError: String?
    private(set) var isVerifying = false

    let profiles: ProfileStore

    init(profiles: ProfileStore = ProfileStore(), defaults: UserDefaults = .standard) {
        self.profiles = profiles
        onboardingDone = defaults.bool(forKey: Self.onboardingKey)
    }

    private var onboardingDone: Bool

    /// Entry point: decide the initial phase from persisted state.
    func bootstrap() async {
        guard let profile = profiles.activeProfile else {
            phase = onboardingDone ? .login : .onboarding
            return
        }
        await activate(profile: profile)
        phase = session != nil ? .authenticated : .login
    }

    func completeOnboarding(defaults: UserDefaults = .standard) {
        onboardingDone = true
        defaults.set(true, forKey: Self.onboardingKey)
        phase = .login
    }

    /// Sign-in with a new credential. Verifies, resolves identity, probes permissions,
    /// persists a new profile, and enters the authenticated phase.
    /// - Parameter onProbed: optional callback with the fresh session (used by tests).
    func login(mode: LoginMode, onProbed: ((Session) -> Void)? = nil) async {
        loginError = nil
        isVerifying = true
        defer { isVerifying = false }

        let auth: AuthConfig
        switch mode {
        case let .token(token):
            auth = .token(token)
        case let .globalKey(email, key):
            auth = .globalKey(email: email, key: key)
        }

        let client = CloudflareClient(auth: auth)
        var addedProfileId: String?

        do {
            // 1. Verify credential upfront (RN parity).
            if case .token = mode {
                let verify: CloudflareResponse<TokenVerification> = try await client.send(CloudflareRequest(path: "/user/tokens/verify"))
                guard verify.result?.status == "active" else {
                    throw CloudflareError.unauthorized
                }
            } else {
                // Global key sanity: /user must respond.
                _ = try await client.sendObject(CloudflareRequest(path: "/user")) as CloudflareUser
            }

            // 2. Persist the profile before identity resolution.
            let profile = try profiles.add(Profile(label: Profile.defaultLabel(for: auth), auth: auth))
            addedProfileId = profile.id

            // 3. Resolve identity (tolerant chain) + probe permissions.
            let newSession = await SessionFactory.makeSession(client: client, profile: profile)
            try? profiles.update(newSession.profileUpdated())

            session = newSession
            onProbed?(newSession)
            phase = .authenticated
        } catch {
            // Roll back the partial profile add so failed logins leave no residue.
            if let id = addedProfileId {
                try? profiles.remove(id: id)
            }
            loginError = Self.friendlyMessage(for: error)
            phase = .login
        }
    }

    /// Switch to another stored profile.
    func switchProfile(_ profile: Profile) async {
        profiles.setActive(id: profile.id)
        await activate(profile: profile)
        if session != nil { phase = .authenticated }
    }

    /// Rebuilds the session for an account switch within the same profile.
    func switchAccount(id: String) async {
        guard let current = session else { return }
        let updated = Session(
            client: current.client,
            profile: current.profile,
            user: current.user,
            accounts: current.accounts,
            accountId: id,
            permissions: current.permissions
        )
        reprobe(session: updated)
        session = updated
    }

    func signOut(profileOnly: Bool = false) {
        if profileOnly {
            // keep profiles; back to login
        } else {
            session = nil
        }
        phase = .login
    }

    // MARK: - Internals

    private func activate(profile: Profile) async {
        let client = CloudflareClient(auth: profile.auth)
        let newSession = await SessionFactory.makeSession(client: client, profile: profile)
        session = newSession
    }

    private func reprobe(session: Session) {
        let client = session.client
        let accountId = session.accountId ?? ""
        let zoneId = session.sampleZoneId ?? ""
        Task {
            let permissions = await PermissionProber(client: client).probe(accountId: accountId, zoneId: zoneId)
            self.session?.permissions = permissions
        }
    }

    static func friendlyMessage(for error: Error) -> String {
        guard let cfError = error as? CloudflareError else {
            return (error as? LocalizedError)?.errorDescription ?? "Sign-in failed. Check your credentials and network."
        }
        switch cfError {
        case .unauthorized:
            return "Invalid API token or key — check it and try again."
        case .rateLimited:
            return "Cloudflare is rate limiting. Wait a minute and retry."
        case let .network(urlError):
            return "Network error: \(urlError.localizedDescription)"
        default:
            return cfError.userMessage
        }
    }
}

/// Credential input for the login form.
enum LoginMode {
    case token(String)
    case globalKey(email: String, key: String)
}

private nonisolated struct TokenVerification: Decodable, Sendable {
    let id: String
    let status: String
}
