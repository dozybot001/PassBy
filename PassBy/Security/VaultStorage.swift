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

    // Only enumerate encrypted snapshots inside this app's own container.
    // No keys or plaintext are read until Face ID and recovery authentication.
    func otherSnapshots() throws -> [VaultStorage] {
        let root = directory.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            .filter { url in
                let attributes = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return url != directory && attributes.isDirectory == true && attributes.isSymbolicLink != true
                    && (url.lastPathComponent == "local" ||
                        (url.lastPathComponent.count == 64 && url.lastPathComponent.allSatisfy { $0.isHexDigit }))
            }
            .map { VaultStorage(directory: $0) }.filter { $0.exists }
    }

    func recoverLocalState(key: SymmetricKey) throws -> LocalVaultState {
        let candidates = exists ? [self] : try otherSnapshots()
        let matches = candidates.compactMap { try? $0.load(key: key) }
        guard let first = matches.first else { throw RecoveryError.wrongNotebook }
        // Never choose an arbitrary version if two local books use this key.
        guard matches.allSatisfy({ $0 == first }) else { throw CloudError.notebookChanged }
        return LocalVaultState(current: first.current, base: Vault(),
            recoveryConfirmed: true, draft: first.draft)
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
