import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct KeyStore {
    private let service = "cn.tenonai.apps.passby.local-vault"
    let ownerID: String
    private var account: String { "aes-gcm-key-v1-" + ownerID }

    func read(context: LAContext) throws -> SymmetricKey {
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw VaultError.missingKey }
            throw VaultError.authenticationFailed
        }
        guard let data = result as? Data, data.count == 32 else { throw VaultError.invalidKey }
        return SymmetricKey(data: data)
    }

    func store(_ key: SymmetricKey) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error
        ) else {
            throw error?.takeRetainedValue() as Error? ?? VaultError.faceIDRequired
        }
        // No notebook exists at first setup. Keychain items can survive uninstall;
        // discard an orphaned key instead of reusing a previous installation's key.
        try delete()
        let data = key.withUnsafeBytes { Data($0) }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data
        ]
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw VaultError.storageFailed
        }
    }

    func delete() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.storageFailed
        }
    }
}
