import CryptoKit
import XCTest
@testable import PassBy

final class RecoveryAndMergeTests: XCTestCase {
    func testRecoveryKeyRoundTripAndChecksum() throws {
        let key = SymmetricKey(size: .bits256)
        let formatted = RecoveryKey.format(key)
        let restored = try RecoveryKey.parse(formatted.lowercased().replacingOccurrences(of: "-", with: " "))
        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, restored.withUnsafeBytes { Data($0) })
        XCTAssertThrowsError(try RecoveryKey.parse("short"))
        var damaged = formatted
        damaged.replaceSubrange(damaged.startIndex...damaged.startIndex,
            with: damaged.first == "A" ? "B" : "A")
        XCTAssertThrowsError(try RecoveryKey.parse(damaged))
    }

    func testIndependentDeviceEditsAreMerged() {
        let a = VaultEntry(title: "Mail", password: "old A")
        let b = VaultEntry(title: "Bank", password: "old B")
        let base = Vault(entries: [a, b])
        var local = base, remote = base
        local.entries[0].password = "new A"
        remote.entries[1].password = "new B"
        let result = VaultMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.conflictCount, 0)
        XCTAssertEqual(result.vault.entries.first { $0.id == a.id }?.password, "new A")
        XCTAssertEqual(result.vault.entries.first { $0.id == b.id }?.password, "new B")
    }

    func testConcurrentPasswordEditsPreserveBothValues() {
        let entry = VaultEntry(title: "Mail", password: "old")
        let base = Vault(entries: [entry])
        var local = base, remote = base
        local.entries[0].password = "mine"
        remote.entries[0].password = "theirs"
        let result = VaultMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.conflictCount, 1)
        XCTAssertEqual(Set(result.vault.entries.map(\.password)), Set(["mine", "theirs"]))
        XCTAssertEqual(Set(result.vault.entries.map(\.id)).count, 2)
    }

    func testDeletionSyncsButCannotDiscardConcurrentEdit() {
        let entry = VaultEntry(title: "Mail", password: "old")
        let base = Vault(entries: [entry])
        let removed = Vault()
        XCTAssertTrue(VaultMerge.merge(base: base, local: removed, remote: base).vault.entries.isEmpty)
        var edited = base
        edited.entries[0].password = "new"
        let result = VaultMerge.merge(base: base, local: removed, remote: edited)
        XCTAssertEqual(result.vault.entries.first?.password, "new")
        XCTAssertEqual(result.conflictCount, 1)
    }

    func testRetryAfterIntegratingConflictDoesNotDuplicateCopy() {
        let entry = VaultEntry(title: "Mail", password: "old")
        let base = Vault(entries: [entry])
        var local = base, remote = base
        local.entries[0].password = "mine"
        remote.entries[0].password = "theirs"
        let integrated = VaultMerge.merge(base: base, local: local, remote: remote).vault
        var newerRemote = remote
        newerRemote.entries[0].notes = "Changed while upload was pending"
        let retried = VaultMerge.merge(base: remote, local: integrated, remote: newerRemote)
        XCTAssertEqual(retried.conflictCount, 0)
        XCTAssertEqual(retried.vault.entries.count, 2)
        XCTAssertEqual(Set(retried.vault.entries.map(\.password)), Set(["mine", "theirs"]))
        XCTAssertEqual(retried.vault.entries.first { $0.id == entry.id }?.notes,
            "Changed while upload was pending")
    }

    func testRemoteFolderDeletionMovesEntryToUnfiled() {
        let folder = VaultFolder(name: "Work")
        let entry = VaultEntry(title: "Mail", folderID: folder.id)
        let base = Vault(folders: [folder], entries: [entry])
        var remote = base
        remote.removeFolder(folder.id)
        let result = VaultMerge.merge(base: base, local: base, remote: remote)
        XCTAssertTrue(result.vault.folders.isEmpty)
        XCTAssertNil(result.vault.entries.first?.folderID)
        XCTAssertNoThrow(try result.vault.validated())
    }
    func testMissingCloudRestorePreservesPreviouslySyncedEntries() throws {
        let vault = Vault(entries: [VaultEntry(title: "Existing test", password: "test-only")])
        let state = LocalVaultState(current: vault, base: vault)
        XCTAssertThrowsError(try state.integratingCloud(nil))
        XCTAssertEqual(try state.integratingCloud(nil, restoringMissingNotebook: true).vault, vault)
        // A real, existing empty cloud book represents deletions. Explicit
        // restore permission must not resurrect those deleted entries.
        XCTAssertTrue(try state.integratingCloud(Vault(), restoringMissingNotebook: true).vault.entries.isEmpty)
    }

    func testRecoveryConfirmationNeedsTheRequestedGroup() {
        let formatted = RecoveryKey.format(SymmetricKey(size: .bits256))
        let groups = formatted.split(separator: "-").map(String.init)
        XCTAssertEqual(RecoveryKey.groupCount(formatted), 17)
        XCTAssertTrue(RecoveryKey.confirms(" " + groups[6].lowercased() + " ", group: 6, of: formatted))
        XCTAssertFalse(RecoveryKey.confirms("ZZZZ", group: 6, of: formatted))
        XCTAssertFalse(RecoveryKey.confirms(formatted, group: 6, of: formatted))
        XCTAssertFalse(RecoveryKey.confirms(groups[0], group: 17, of: formatted))
    }

    func testDeletedEntriesStayLocallyAndExpireAfterThirtyDays() {
        let kept = VaultEntry(title: "Mail", password: "a")
        let removed = VaultEntry(title: "Bank", password: "b")
        let previous = Vault(entries: [kept, removed])
        var state = LocalVaultState(current: Vault(entries: [kept]), base: previous)
        let now = Date(timeIntervalSince1970: 1_000_000)
        state.keepDeleted(from: previous, now: now)
        XCTAssertEqual(state.recentlyDeleted.map(\.entry), [removed])
        state.pruneDeleted(now: now.addingTimeInterval(LocalVaultState.deletedLifetime - 1))
        XCTAssertEqual(state.recentlyDeleted.count, 1)
        state.pruneDeleted(now: now.addingTimeInterval(LocalVaultState.deletedLifetime))
        XCTAssertTrue(state.recentlyDeleted.isEmpty)
    }

    func testDeletionFromAnotherDeviceIsKeptAfterMerge() throws {
        let entry = VaultEntry(title: "Mail", password: "secret")
        let synced = Vault(entries: [entry])
        var state = LocalVaultState(current: synced, base: synced)
        let merge = try state.integratingCloud(Vault())
        let previous = state.current
        state.current = merge.vault
        state.keepDeleted(from: previous)
        XCTAssertTrue(state.current.entries.isEmpty)
        XCTAssertEqual(state.recentlyDeleted.first?.entry.password, "secret")
    }

    func testRestoredEntryLeavesRecentlyDeletedAndReturnsToUnfiledWithoutItsFolder() {
        let folder = VaultFolder(name: "Old")
        let entry = VaultEntry(title: "Mail", folderID: folder.id)
        let previous = Vault(folders: [folder], entries: [entry])
        var state = LocalVaultState(current: Vault(), base: previous)
        state.keepDeleted(from: previous)
        var restored = state.current
        restored.save(state.recentlyDeleted[0].entry)
        let before = state.current
        state.current = restored
        state.keepDeleted(from: before)
        XCTAssertTrue(state.recentlyDeleted.isEmpty)
        XCTAssertNil(state.current.entries.first?.folderID)
    }

    func testLocalStateSavedBeforeRecentlyDeletedStillOpens() throws {
        let key = SymmetricKey(size: .bits256)
        let state = LocalVaultState(current: Vault(entries: [VaultEntry(title: "Mail")]), base: Vault(),
            draft: VaultEntry(title: "Draft"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "recentlyDeleted")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(LocalVaultState.self, from: legacy)
        XCTAssertEqual(decoded, state)
        var deleted = state
        deleted.recentlyDeleted = [DeletedEntry(entry: VaultEntry(title: "Gone", password: "p"), deletedAt: Date())]
        XCTAssertEqual(try VaultCipher.openLocal(VaultCipher.sealLocal(deleted, key: key), key: key), deleted)
        // Recently Deleted never enters the synced notebook.
        let synced = try VaultCipher.open(VaultCipher.seal(deleted.current, key: key), key: key)
        XCTAssertFalse(synced.entries.contains { $0.title == "Gone" })
    }
}
