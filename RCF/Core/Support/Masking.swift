import Foundation

/// Privacy masking for tokens, emails, and domains shown on screen.
/// Pure functions; usable from any executor.
nonisolated enum Masking {
    /// Defaults ON when the preference has never been written.
    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "rcf.privacy.maskSensitive") != nil else { return true }
        return defaults.bool(forKey: "rcf.privacy.maskSensitive")
    }

    /// `dev.8ugust.rcf`-style identifiers: keep first 4 + last 4, mask the rest.
    static func token(_ value: String) -> String {
        guard isEnabled else { return value }
        guard value.count > 8 else { return String(repeating: "•", count: value.count) }
        return "\(value.prefix(4))••••\(value.suffix(4))"
    }

    /// `john.doe@example.com` → `j•••@e••••.com`.
    static func email(_ value: String) -> String {
        guard isEnabled else { return value }
        let parts = value.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return String(repeating: "•", count: value.count) }
        let local = parts[0]
        let domainParts = parts[1].split(separator: ".", maxSplits: 1)
        let domain = domainParts[0]
        let tld = domainParts.count > 1 ? ".\(domainParts[1])" : ""
        return "\(local.prefix(1))•••@\(domain.prefix(1))•••\(tld)"
    }

    /// Domain privacy: keep TLD, mask labels: `my-site.example.com` → `m•••.example.com`.
    static func domain(_ value: String) -> String {
        guard isEnabled else { return value }
        let parts = value.split(separator: ".")
        guard parts.count >= 2 else { return value }
        let masked = parts.dropLast(1).map { "\($0.prefix(1))•••" }
        return (masked + [String(parts.last!)]).joined(separator: ".")
    }
}
