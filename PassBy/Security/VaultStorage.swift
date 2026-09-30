import CryptoKit
import Foundation

enum VaultCipher {
    private static let associatedData = Data("PassBy.local-notebook.v1".utf8)

    static func seal(_ vault: Vault, key: SymmetricKey) throws -> Data {
        let plaintext = try JSONEncoder().encode(vault.validated())
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: associatedData)
        guard let data = sealed.combined else { throw VaultError.invalidData }
        return data
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> Vault {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: associatedData)
            return try JSONDecoder().decode(Vault.self, from: plaintext).validated()
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.invalidData
        }
    }

    static func sealLocal(_ state: LocalVaultState, key: SymmetricKey) throws -> Data {
        _ = try state.current.validated()
        _ = try state.base.validated()
        let data = try JSONEncoder().encode(state)
        let box = try AES.GCM.seal(data, using: key,
            authenticating: Data("PassBy.local-state.v1".utf8))
        guard let ciphertext = box.combined else { throw VaultError.invalidData }
        return ciphertext
    }

    static func openLocal(_ data: Data, key: SymmetricKey) throws -> LocalVaultState {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(box, using: key,
                authenticating: Data("PassBy.local-state.v1".utf8))
            let state = try JSONDecoder().decode(LocalVaultState.self, from: plaintext)
            _ = try state.current.validated()
            _ = try state.base.validated()
            return state
        } catch { throw VaultError.invalidData }
    }
}

struct VaultStorage {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("notebook.passby", isDirectory: false) }
    var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    init(directory: URL? = nil, ownerID: String? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("PassBy", isDirectory: true)
            .appendingPathComponent(ownerID ?? "local", isDirectory: true)
    }

    func load(key: SymmetricKey) throws -> LocalVaultState {
        try VaultCipher.openLocal(Data(contentsOf: fileURL), key: key)
    }

    func save(_ state: LocalVaultState, key: SymmetricKey) throws {
        let ciphertext = try VaultCipher.sealLocal(state, key: key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        try protect(directory)
        try ciphertext.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try protect(fileURL)
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                              ofItemAtPath: url.path)
        var protectedURL = url
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try protectedURL.setResourceValues(resources)
    }

    func erase() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
