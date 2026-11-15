import CryptoKit
import XCTest
@testable import PassBy

final class VaultTests: XCTestCase {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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

    func testInvalidNotebookIsRejected() throws {
        var vault = Vault()
        vault.schemaVersion = 999
        XCTAssertThrowsError(try vault.validated())
        let folder = VaultFolder(name: "Work")
        XCTAssertThrowsError(try Vault(folders: [folder, folder]).validated())
        XCTAssertThrowsError(try Vault(entries: [VaultEntry(title: "Mail", folderID: UUID())]).validated())
    }

    // MARK: The file on this iPhone

    func testStoreRoundTripKeepsThePreviousFileAndStaysInBackups() throws {
        let store = NotebookStore(directory: temporaryFolder())
        defer { try? FileManager.default.removeItem(at: store.directory) }
        XCTAssertFalse(store.exists)
        XCTAssertEqual(try store.load(), Notebook())
        var first = Notebook()
        first.vault.entries = [VaultEntry(title: "Mail", password: "one")]
        try store.save(first)
        XCTAssertEqual(try store.load(), first)
        XCTAssertNotEqual(try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        var second = first
        second.vault.entries.append(VaultEntry(title: "Bank", password: "two"))
        try store.save(second)
        XCTAssertEqual(try store.load(), second)
        XCTAssertEqual(try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: store.previousURL)), first)
        #if !targetEnvironment(simulator)
        // The simulator has no data-protection keybag and omits this attribute.
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
        #endif
    }

    func testDamagedFileFallsBackToThePreviousOneAndIsNeverOverwrittenWhenBothFail() throws {
        let store = NotebookStore(directory: temporaryFolder())
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var first = Notebook()
        first.vault.entries = [VaultEntry(title: "Mail")]
        var second = first
        second.vault.entries.append(VaultEntry(title: "Bank"))
        try store.save(first)
        try store.save(second)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(try store.load(), first)
        try Data("also not json".utf8).write(to: store.previousURL)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? VaultError, .invalidData) }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), Data("not json".utf8))
        XCTAssertEqual(try Data(contentsOf: store.previousURL), Data("also not json".utf8))
    }

    func testFileFromANewerVersionIsNotOpened() throws {
        let store = NotebookStore(directory: temporaryFolder())
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        var newer = Notebook()
        newer.fileVersion = Notebook.fileVersion + 1
        try JSONEncoder().encode(newer).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? VaultError, .unsupportedVersion) }
        XCTAssertThrowsError(try store.save(newer))
    }

    // MARK: Recently Deleted and the export reminder

    func testDeletedEntriesStayThirtyDaysAndRestoringRemovesTheCopy() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let folder = VaultFolder(name: "Work")
        let entry = VaultEntry(title: "Mail", password: "p", folderID: folder.id)
        var notebook = Notebook()
        notebook.update(Vault(folders: [folder], entries: [entry]), now: now)
        notebook.update(Vault(folders: [folder]), now: now)
        XCTAssertEqual(notebook.recentlyDeleted.map(\.entry), [entry])
        notebook.pruneDeleted(now: now.addingTimeInterval(Notebook.deletedLifetime - 1))
        XCTAssertEqual(notebook.recentlyDeleted.count, 1)
        var restored = notebook.vault
        restored.save(entry)
        notebook.update(restored, now: now)
        XCTAssertTrue(notebook.recentlyDeleted.isEmpty)
        notebook.update(Vault(), now: now)
        notebook.pruneDeleted(now: now.addingTimeInterval(Notebook.deletedLifetime))
        XCTAssertTrue(notebook.recentlyDeleted.isEmpty)
    }

    func testExportReminderShowsWhenNeverExportedOrChangedAfterThirtyDays() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let month = Notebook.exportReminderInterval
        var notebook = Notebook()
        XCTAssertFalse(notebook.needsExportReminder(now: now))
        notebook.update(Vault(entries: [VaultEntry(title: "Mail")]), now: now)
        XCTAssertTrue(notebook.needsExportReminder(now: now))
        notebook.exportReminderDismissedAt = now
        XCTAssertFalse(notebook.needsExportReminder(now: now.addingTimeInterval(month - 1)))
        XCTAssertTrue(notebook.needsExportReminder(now: now.addingTimeInterval(month)))
        notebook.lastExportAt = now
        notebook.changedSinceExport = false
        notebook.exportReminderDismissedAt = nil
        XCTAssertFalse(notebook.needsExportReminder(now: now.addingTimeInterval(2 * month)))
        notebook.update(Vault(entries: [VaultEntry(title: "Mail"), VaultEntry(title: "Bank")]), now: now)
        XCTAssertFalse(notebook.needsExportReminder(now: now.addingTimeInterval(month - 1)))
        XCTAssertTrue(notebook.needsExportReminder(now: now.addingTimeInterval(month)))
    }

    // MARK: Notebooks left by 1.x

    /// What 1.x wrote: AES-GCM over the JSON of its local state.
    private struct OldState: Encodable {
        var current: Vault
        var base = Vault()
        var recoveryConfirmed = true
        var draft: VaultEntry?
        var recentlyDeleted: [DeletedEntry]?
    }

    private func writeOld(_ state: OldState, named name: String, in root: URL, key: SymmetricKey) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let box = try AES.GCM.seal(JSONEncoder().encode(state), using: key, authenticating: Data("PassBy.local-state.v1".utf8))
        let file = folder.appendingPathComponent("notebook.passby")
        try XCTUnwrap(box.combined).write(to: file)
        return file
    }

    func testOldNotebooksAreFoundByFolderAndReadWithoutBeingChanged() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256)
        let draft = VaultEntry(title: "Draft", password: "draft-only")
        let vault = Vault(entries: [VaultEntry(title: "Mail", password: "p")])
        let hashed = String(repeating: "a", count: 64)
        let file = try writeOld(OldState(current: vault, draft: draft), named: hashed, in: root, key: key)
        _ = try writeOld(OldState(current: Vault()), named: "local", in: root, key: key)
        _ = try writeOld(OldState(current: Vault()), named: "not-a-notebook", in: root, key: key)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(String(repeating: "b", count: 64)), withIntermediateDirectories: true)
        let before = try Data(contentsOf: file)
        let found = LegacyNotebook.all(root: root)
        XCTAssertEqual(found.map(\.name), [hashed, "local"])
        let state = try found[0].open(key: key)
        XCTAssertEqual(state.current, vault)
        XCTAssertEqual(state.draft, draft)
        XCTAssertEqual(state.recentlyDeleted, [])
        XCTAssertThrowsError(try found[0].open(key: SymmetricKey(size: .bits256)))
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testMigrationCarriesEveryBookItsDraftAndRecentlyDeleted() throws {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let work = VaultFolder(name: "Work")
        let shared = VaultEntry(title: "Mail", account: "a", password: "p", folderID: work.id)
        let deleted = DeletedEntry(entry: VaultEntry(title: "Old", password: "gone"), deletedAt: now.addingTimeInterval(-60))
        let first = LegacyState(current: Vault(folders: [work], entries: [shared, VaultEntry(title: "Bank", password: "b")]),
            draft: VaultEntry(title: "Half", password: "h", folderID: work.id), recentlyDeleted: [deleted])
        var changed = shared
        changed.password = "different"
        // The second book has the same entry once unchanged in a same-named folder, and once changed.
        let otherWork = VaultFolder(name: "Work")
        let second = LegacyState(current: Vault(folders: [otherWork],
            entries: [changed, VaultEntry(title: "Shop", password: "s", folderID: otherWork.id)]))
        var notebook = Notebook()
        let summary = try Migration.carry([("a", first), ("local", second)], into: &notebook, draftMarker: " (Unsaved draft)", now: now)
        XCTAssertEqual(summary.entries, 4)
        XCTAssertEqual(summary.drafts, ["Half (Unsaved draft)"])
        XCTAssertEqual(notebook.vault.folders, [work])
        XCTAssertEqual(notebook.vault.entries.map(\.title).sorted(), ["Bank", "Half (Unsaved draft)", "Mail", "Mail", "Shop"])
        XCTAssertEqual(Set(notebook.vault.entries.filter { $0.title == "Mail" }.map(\.password)), ["p", "different"])
        XCTAssertEqual(notebook.vault.entries.first { $0.title == "Shop" }?.folderID, work.id)
        XCTAssertEqual(notebook.vault.entries.first { $0.title == "Half (Unsaved draft)" }?.folderID, work.id)
        XCTAssertEqual(notebook.recentlyDeleted.map(\.entry.title), ["Old"])
        XCTAssertEqual(notebook.migratedLegacy, ["a", "local"])
        XCTAssertNoThrow(try notebook.validated())
        // Running it again adds nothing.
        let again = notebook
        _ = try Migration.carry([("a", first)], into: &notebook, draftMarker: " (Unsaved draft)", now: now)
        XCTAssertEqual(notebook.vault.entries.count, again.vault.entries.count + 1) // the draft is copied again, nothing else
        XCTAssertEqual(notebook.recentlyDeleted, again.recentlyDeleted)
    }

    func testMigrationKeepsWhatIsAlreadyInTheNotebook() throws {
        var notebook = Notebook()
        notebook.vault.entries = [VaultEntry(title: "New", password: "n")]
        let old = LegacyState(current: Vault(entries: [VaultEntry(title: "Mail", password: "p")]))
        _ = try Migration.carry([("local", old)], into: &notebook)
        XCTAssertEqual(notebook.vault.entries.map(\.title).sorted(), ["Mail", "New"])
    }

    func testRecoveryKeyOfAnOldNotebookIsParsedAndChecked() throws {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let hex = (data + Data(SHA256.hash(data: data)).prefix(2)).map { String(format: "%02X", $0) }.joined()
        let grouped = stride(from: 0, to: hex.count, by: 4).map { offset -> String in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return String(hex[start..<hex.index(start, offsetBy: 4)])
        }.joined(separator: "-")
        XCTAssertEqual(try RecoveryKey.parse(grouped.lowercased()).withUnsafeBytes { Data($0) }, data)
        XCTAssertThrowsError(try RecoveryKey.parse(String(grouped.dropLast())))
        var wrong = Array(hex)
        wrong[0] = wrong[0] == "0" ? "1" : "0"
        XCTAssertThrowsError(try RecoveryKey.parse(String(wrong)))
    }
}

#if targetEnvironment(simulator)
import SwiftUI

/// Renders every screen with a fictional notebook and writes PNGs, when the
/// folder named by SNAPSHOT_DIR exists. Not a pass/fail test of appearance:
/// it lets a person, or a review, look at each page without tapping through.
@MainActor
final class ScreenSnapshots: XCTestCase {
    func testRenderEveryScreen() async throws {
        let folder = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? "/tmp/passby-snapshots"
        guard FileManager.default.fileExists(atPath: folder) else { throw XCTSkip("no snapshot folder") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotebookStore(directory: root)
        let work = VaultFolder(name: "工作")
        let mail = VaultEntry(title: "个人邮箱", account: "alex@example.com", password: "example-only-1", notes: "虚构数据\n第二行")
        var notebook = Notebook()
        notebook.update(Vault(folders: [work], entries: [mail,
            VaultEntry(title: "公司邮箱", account: "alex@example.org", password: "example-only-2", folderID: work.id),
            VaultEntry(title: "路由器", password: "example-only-3"),
            VaultEntry(title: "旧账号", account: "old@example.com", password: "example-only-4")]))
        var next = notebook.vault
        next.entries.removeLast()
        notebook.update(next)
        try store.save(notebook)
        let suite = "passby-snapshots-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "gateEnabled")
        defaults.set(true, forKey: "noLockNoticeShown")
        let session = VaultSession(store: store, defaults: defaults)
        await session.unlock()
        XCTAssertEqual(session.phase, .unlocked)
        XCTAssertEqual(session.vault.entries.count, 3)

        let locked = VaultSession(store: store, defaults: try XCTUnwrap(UserDefaults(suiteName: suite + "-locked")))
        let screens: [(String, AnyView)] = [
            ("01-lock", AnyView(LockView().environmentObject(locked))),
            ("02-list", AnyView(LibraryView())),
            ("03-detail", AnyView(NavigationStack { EntryDetailView(id: mail.id) })),
            ("04-editor", AnyView(EntryEditorView(entry: mail, isNew: false))),
            ("05-generator", AnyView(PasswordGeneratorView(copyOnly: true) { _ in true })),
            ("06-folders", AnyView(FoldersView())),
            ("07-settings", AnyView(SettingsView())),
            ("08-export", AnyView(ExportView())),
            ("09-import", AnyView(ImportView())),
            ("10-deleted", AnyView(NavigationStack { RecentlyDeletedView() })),
            ("11-privacy", AnyView(NavigationStack { PrivacyPolicyView() })),
            ("12-about", AnyView(NavigationStack { AboutPassByView() })),
            ("13-migration", AnyView(MigrationView())),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, view) in screens {
                let controller = UIHostingController(rootView: ZStack { Palette.paper.ignoresSafeArea(); view }
                    .environmentObject(session).tint(Palette.accent).foregroundStyle(Palette.ink))
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.overrideUserInterfaceStyle = style
                window.rootViewController = controller
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(600))
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let suffix = style == .dark ? "-dark" : ""
                try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + suffix + ".png"))
                window.isHidden = true
            }
        }
    }
}
#endif
