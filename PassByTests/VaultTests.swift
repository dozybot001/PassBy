import CryptoKit
import XCTest
@testable import PassBy

final class VaultTests: XCTestCase {
    func testEncryptedRoundTripAndNoPlaintextOnDisk() throws {
        let key = SymmetricKey(size: .bits256)
        let folder = VaultFolder(name: "Private folder")
        let entry = VaultEntry(title: "Private title", account: "me@example.test",
            password: "never-plaintext-37", notes: "Private notes", folderID: folder.id)
        let vault = Vault(folders: [folder], entries: [entry])
        let ciphertext = try VaultCipher.seal(vault, key: key)
        XCTAssertEqual(try VaultCipher.open(ciphertext, key: key), vault)
        for value in [entry.title, entry.account, entry.password, entry.notes, folder.name] {
            XCTAssertNil(ciphertext.range(of: Data(value.utf8)))
        }
        XCTAssertNotEqual(ciphertext, try VaultCipher.seal(vault, key: key))
    }

    func testTamperedDataAndWrongKeyAreRejected() throws {
        let key = SymmetricKey(size: .bits256)
        var ciphertext = try VaultCipher.seal(Vault(entries: [VaultEntry(title: "Mail")]), key: key)
        ciphertext[ciphertext.count / 2] ^= 1
        XCTAssertThrowsError(try VaultCipher.open(ciphertext, key: key))
        let valid = try VaultCipher.seal(Vault(), key: key)
        XCTAssertThrowsError(try VaultCipher.open(valid, key: SymmetricKey(size: .bits256)))
    }

    func testDeletingFolderPreservesEveryCredential() {
        let folder = VaultFolder(name: "Work")
        let entry = VaultEntry(title: "Mail", account: "a", password: "p", notes: "n", folderID: folder.id)
        var vault = Vault(folders: [folder], entries: [entry])
        vault.removeFolder(folder.id)
        XCTAssertTrue(vault.folders.isEmpty)
        XCTAssertEqual(vault.entries.count, 1)
        XCTAssertNil(vault.entries[0].folderID)
        XCTAssertEqual(vault.entries[0].password, "p")
    }

    func testInvalidSchemaDoesNotOpen() throws {
        var vault = Vault()
        vault.schemaVersion = 999
        XCTAssertThrowsError(try VaultCipher.seal(vault, key: SymmetricKey(size: .bits256)))
        let folder = VaultFolder(name: "Work")
        XCTAssertThrowsError(try Vault(folders: [folder, folder]).validated())
    }

    func testLocalSnapshotUsesSeparateAuthenticationDomain() throws {
        let key = SymmetricKey(size: .bits256)
        let state = LocalVaultState(current: Vault(entries: [VaultEntry(title: "Mail")]), base: Vault())
        let local = try VaultCipher.sealLocal(state, key: key)
        XCTAssertEqual(try VaultCipher.openLocal(local, key: key), state)
        XCTAssertThrowsError(try VaultCipher.open(local, key: key))
        XCTAssertThrowsError(try VaultCipher.openLocal(VaultCipher.seal(Vault(), key: key), key: key))
    }

    func testProtectedStorageRoundTripAndBackupExclusion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = VaultStorage(directory: folder)
        let key = SymmetricKey(size: .bits256)
        let state = LocalVaultState(current: Vault(entries: [VaultEntry(title: "Mail", password: "secret")]), base: Vault())
        try storage.save(state, key: key)
        XCTAssertEqual(try storage.load(key: key), state)
        XCTAssertEqual(try storage.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        #if !targetEnvironment(simulator)
        // The simulator has no device data-protection keybag and omits this
        // attribute. Verify complete protection on physical iOS hardware.
        let attributes = try FileManager.default.attributesOfItem(atPath: storage.fileURL.path)
        XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
        #endif
        try storage.erase()
        XCTAssertFalse(storage.exists)
    }
    func testLocalRecoveryKeepsOriginalCiphertextAndDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = VaultStorage(directory: root.appendingPathComponent(String(repeating: "a", count: 64)))
        let destination = VaultStorage(directory: root.appendingPathComponent(String(repeating: "b", count: 64)))
        let key = SymmetricKey(size: .bits256)
        let vault = Vault(entries: [VaultEntry(title: "Local test", password: "test-only")])
        let draft = VaultEntry(title: "Draft", password: "draft-only")
        let state = LocalVaultState(current: vault, base: vault, recoveryConfirmed: true, draft: draft)
        try original.save(state, key: key)
        let originalBytes = try Data(contentsOf: original.fileURL)
        XCTAssertEqual(try destination.otherSnapshots().count, 1)
        XCTAssertThrowsError(try destination.recoverLocalState(key: SymmetricKey(size: .bits256)))
        let restored = try destination.recoverLocalState(key: key)
        XCTAssertEqual(restored.current, vault)
        XCTAssertEqual(restored.base, Vault())
        XCTAssertEqual(restored.draft, draft)
        try destination.save(restored, key: key)
        XCTAssertEqual(try Data(contentsOf: original.fileURL), originalBytes)
        XCTAssertEqual(try original.load(key: key), state)
    }

    func testLocalRecoveryRejectsAmbiguousSnapshots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256)
        for (name, title) in [("a", "First"), ("b", "Second")] {
            let store = VaultStorage(directory: root.appendingPathComponent(String(repeating: name, count: 64)))
            try store.save(LocalVaultState(current: Vault(entries: [VaultEntry(title: title)]), base: Vault()), key: key)
        }
        let destination = VaultStorage(directory: root.appendingPathComponent(String(repeating: "c", count: 64)))
        XCTAssertThrowsError(try destination.recoverLocalState(key: key))
        XCTAssertFalse(destination.exists)
    }

}
