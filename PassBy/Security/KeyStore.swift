import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Reads the key of a PassBy 1.x notebook during migration. 2.0 stores no key
/// of its own, and it never changes or deletes the old one.
struct LegacyKeyStore {
    private let service = "cn.tenonai.apps.passby.local-vault"
    let ownerID: String

    /// `context` must already have passed a biometric check: the old key is
    /// bound to the Face ID or Touch ID enrollment that existed when it was saved.
    func read(context: LAContext) throws -> SymmetricKey {
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "aes-gcm-key-v1-" + ownerID,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 32 else { throw LegacyKeyError.unavailable }
        return SymmetricKey(data: data)
    }
}

enum LegacyKeyError: Error { case unavailable }
