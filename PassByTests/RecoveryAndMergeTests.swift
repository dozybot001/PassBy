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
}
