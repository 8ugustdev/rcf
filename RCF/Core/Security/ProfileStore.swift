import Foundation

/// Multi-account profile store: list/add/remove/rename/setActive, persisted as
/// JSON in the Keychain (RN `profiles.ts` parity).
@MainActor
@Observable
final class ProfileStore {
    nonisolated static let profilesAccount = "rcf.profiles"
    nonisolated static let activeKey = "rcf.active.profile"

    private let keychain: KeychainStore
    private let defaults: UserDefaults

    private(set) var profiles: [Profile] = []
    private(set) var activeProfileId: String?

    init(keychain: KeychainStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        load()
    }

    /// The active profile, if any.
    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileId }
    }

    /// Adds a profile and makes it active. Returns the stored profile.
    @discardableResult
    func add(_ profile: Profile) throws -> Profile {
        profiles.append(profile)
        activeProfileId = profile.id
        try save()
        return profile
    }

    func remove(id: String) throws {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
        }
        try save()
    }

    func rename(id: String, to label: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].label = label
        try save()
    }

    /// Updates stored metadata (e.g. resolved accountId) for a profile.
    func update(_ profile: Profile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        try save()
    }

    func setActive(id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        defaults.set(id, forKey: Self.activeKey)
    }

    /// Signs out entirely: wipes profiles and the active pointer.
    func removeAll() throws {
        profiles = []
        activeProfileId = nil
        try keychain.delete(account: Self.profilesAccount)
        defaults.removeObject(forKey: Self.activeKey)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? keychain.read(account: Self.profilesAccount),
              let list = try? JSONDecoder().decode([Profile].self, from: data) else {
            return
        }
        profiles = list
        let savedActive = defaults.string(forKey: Self.activeKey)
        activeProfileId = savedActive.flatMap { id in list.contains { $0.id == id } ? id : nil } ?? list.first?.id
        if activeProfileId != nil, savedActive != activeProfileId {
            defaults.set(activeProfileId, forKey: Self.activeKey)
        }
    }

    private func save() throws {
        let data = try JSONEncoder().encode(profiles)
        try keychain.write(data, account: Self.profilesAccount)
        if let activeProfileId {
            defaults.set(activeProfileId, forKey: Self.activeKey)
        }
    }
}
