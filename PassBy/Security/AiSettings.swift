import Foundation
import Security

/// Where AI grouping keeps its two small items. The app uses the Keychain; tests use memory.
protocol AiSecretStore {
    func read(_ name: String) -> Data?
    func write(_ name: String, _ data: Data) -> Bool
    func remove(_ name: String)
}

/// Generic passwords of this app only: readable while the iPhone is unlocked, never synced through
/// iCloud Keychain, and never restored onto another device from a backup.
struct AiKeychain: AiSecretStore {
    private let service: String

    /// Tests pass a service of their own, so that they never touch the items the app saved.
    init(service: String = "cn.tenonai.passby.ai") { self.service = service }

    private func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name,
         kSecAttrSynchronizable as String: false]
    }

    func read(_ name: String) -> Data? {
        var query = query(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func write(_ name: String, _ data: Data) -> Bool {
        SecItemDelete(query(name) as CFDictionary)
        var item = query(name)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func remove(_ name: String) {
        SecItemDelete(query(name) as CFDictionary)
    }
}

/// Whether AI grouping is on, where it sends requests, and the person's API key.
///
/// None of it is in the notebook file, so an export, which holds only entries and folders, carries
/// none of it. The API key is kept together with the host and port it was saved for: a key saved
/// for one provider is never read back for another. Turning the feature off removes all of it.
struct AiSettings {
    struct Config: Codable, Equatable {
        var endpoint: String
        var model: String
    }

    private struct SavedKey: Codable {
        var host: String
        var key: String
    }

    private static let settingsName = "settings"
    private static let keyName = "key"
    private let store: AiSecretStore

    init(store: AiSecretStore = AiKeychain()) { self.store = store }

    /// Nil while the feature is off, which is how it starts.
    func load() -> Config? {
        store.read(Self.settingsName).flatMap { try? JSONDecoder().decode(Config.self, from: $0) }
    }

    /// Turns the feature on, or changes where it sends. A key saved for a different host or port is removed.
    @discardableResult
    func save(_ config: Config) -> Bool {
        let authority = AiGrouping.endpoint(config.endpoint)?.authority
        if authority == nil || savedKey()?.host != authority { removeKey() }
        guard let data = try? JSONEncoder().encode(config) else { return false }
        return store.write(Self.settingsName, data)
    }

    /// Turns the feature off: the settings and the API key both go.
    func turnOff() {
        removeKey()
        store.remove(Self.settingsName)
    }

    var hasKey: Bool { savedKey() != nil }

    private func savedKey() -> SavedKey? {
        store.read(Self.keyName).flatMap { try? JSONDecoder().decode(SavedKey.self, from: $0) }
    }

    /// Saves the key for `host`, which is a host and port as in `AiGrouping.Endpoint.authority`.
    @discardableResult
    func saveKey(_ apiKey: String, host: String) -> Bool {
        guard let data = try? JSONEncoder().encode(SavedKey(host: host, key: apiKey)) else { return false }
        return store.write(Self.keyName, data)
    }

    /// The API key, if one is saved for exactly `host`.
    func key(host: String) -> String? {
        guard let saved = savedKey(), saved.host == host else { return nil }
        return saved.key
    }

    func removeKey() {
        store.remove(Self.keyName)
    }
}
