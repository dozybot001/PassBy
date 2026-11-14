import XCTest
@testable import PassBy

final class ExportAndImportTests: XCTestCase {
    // MARK: The shared test vectors (docs/export-vectors.json)

    private struct Vectors: Decodable {
        struct Valid: Decodable {
            let name: String, typed: String, equivalentInputs: [String], kind: String
            let secretHex: String, iterations: Int, saltHex: String, nonceHex: String
            let plaintext: String, fileBase64: String
        }
        struct Invalid: Decodable { let name: String, typed: String, fileBase64: String, error: String }
        struct Rule: Decodable { let typed: String, problem: String? }
        let valid: [Valid], invalid: [Invalid], passphraseRules: [Rule]
    }

    private func vectors() throws -> Vectors {
        // The tests read the repository's file directly; there is one copy for every platform.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/export-vectors.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    private func bytes(_ hex: String) -> Data {
        var data = Data(), index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    private func errorCode(_ error: Error) -> String? {
        switch error as? ExportError {
        case .notExport: return "notExport"
        case .update: return "update"
        case .damaged: return "damaged"
        case .wrongCode: return "wrongCode"
        case nil: return nil
        }
    }

    func testEveryValidVectorOpensAndIsReproducedByteForByte() throws {
        let all = try vectors()
        XCTAssertEqual(all.valid.count, 5)
        for vector in all.valid {
            let file = try XCTUnwrap(Data(base64Encoded: vector.fileBase64), vector.name)
            let plaintext = Data(vector.plaintext.utf8)
            for typed in [vector.typed] + vector.equivalentInputs {
                XCTAssertEqual(ExportFormat.secretBytes(typed), bytes(vector.secretHex), "\(vector.name): \(typed)")
                XCTAssertEqual(try ExportFormat.decrypt(file, typed: typed), plaintext, "\(vector.name): \(typed)")
            }
            XCTAssertEqual(ExportFormat.canonicalCode(vector.typed) != nil, vector.kind == "code", vector.name)
            XCTAssertNoThrow(try ExportFormat.open(file, typed: vector.typed), vector.name)
            let sealed = try ExportFormat.seal(plaintext: plaintext, secret: bytes(vector.secretHex),
                salt: bytes(vector.saltHex), nonce: bytes(vector.nonceHex), iterations: vector.iterations)
            XCTAssertEqual(sealed, file, vector.name)
        }
    }

    func testEveryInvalidVectorReportsItsError() throws {
        let all = try vectors()
        XCTAssertEqual(all.invalid.count, 10)
        for vector in all.invalid {
            let file = try XCTUnwrap(Data(base64Encoded: vector.fileBase64), vector.name)
            XCTAssertThrowsError(try ExportFormat.open(file, typed: vector.typed), vector.name) {
                XCTAssertEqual(errorCode($0), vector.error, vector.name)
            }
        }
    }

    func testPassphraseRulesMatchTheVectors() throws {
        for rule in try vectors().passphraseRules {
            XCTAssertEqual(ExportFormat.passphraseProblem(rule.typed)?.rawValue, rule.problem, rule.typed)
        }
    }

    // MARK: Export

    func testNewExportCodesAreTwentyCharactersInFourGroups() {
        let codes = (0..<50).map { _ in ExportFormat.newCode() }
        for code in codes {
            XCTAssertEqual(code.split(separator: "-").map(\.count), [5, 5, 5, 5])
            XCTAssertEqual(ExportFormat.canonicalCode(code), code.replacingOccurrences(of: "-", with: ""))
            XCTAssertNil(code.rangeOfCharacter(from: CharacterSet(charactersIn: "ILOUilou")))
        }
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testExportRoundTripKeepsEveryFieldAndHidesThePlaintext() throws {
        let folder = VaultFolder(name: "工作 Work")
        let vault = Vault(folders: [folder], entries: [
            VaultEntry(title: "个人邮箱", account: "alex@example.com", password: "p@ss 密码 🔑", notes: "第一行\nsecond line", folderID: folder.id),
            VaultEntry(title: "Café", account: "", password: "x", notes: "")])
        let code = ExportFormat.newCode()
        let file = try ExportFormat.export(vault, typed: code, now: Date(timeIntervalSince1970: 1_794_657_600))
        XCTAssertNil(file.range(of: Data("alex@example.com".utf8)))
        let payload = try ExportFormat.open(file, typed: code.lowercased().replacingOccurrences(of: "-", with: " "))
        XCTAssertEqual(payload.vault, vault)
        XCTAssertEqual(payload.format, 1)
        XCTAssertEqual(payload.exportedAt, "2026-11-14T12:00:00Z")
        XCTAssertNotEqual(file, try ExportFormat.export(vault, typed: code))
        XCTAssertThrowsError(try ExportFormat.open(file, typed: ExportFormat.newCode())) { XCTAssertEqual(self.errorCode($0), "wrongCode") }
        XCTAssertNoThrow(try ExportFormat.inspect(file))
        XCTAssertThrowsError(try ExportFormat.inspect(Data("hello".utf8)))
        XCTAssertTrue(ExportFormat.fileName(now: Date(timeIntervalSince1970: 1_794_657_600)).hasSuffix(".passby"))
    }

    func testPlaintextThatBreaksTheRulesIsReportedAsDamagedOrNewer() {
        let folder = "6F1C2A4E-8B3D-4C5E-9F60-1A2B3C4D5E6F", entry = "0E8F6A2B-1C3D-4E5F-8A9B-0C1D2E3F4A5B"
        func parse(_ json: String) -> String? {
            do { _ = try ExportFormat.parse(Data(json.utf8)); return "ok" } catch { return errorCode(error) }
        }
        let item = #"{"id":"\#(entry)","title":"t","account":"","password":"p","notes":""}"#
        XCTAssertEqual(parse(#"{"format":1,"exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[\#(item)],"extra":true}"#), "ok")
        XCTAssertEqual(parse(#"{"format":1,"exportedAt":"2026-11-14T12:00:00Z","folders":[{"id":"\#(folder.lowercased())","name":"f"}],"entries":[{"id":"\#(entry)","title":"t","account":"","password":"p","notes":"","folderID":"\#(folder)"}]}"#), "ok")
        XCTAssertEqual(parse(#"{"format":2,"exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[]}"#), "update")
        XCTAssertEqual(parse(#"{"format":1.5,"exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[]}"#), "damaged")
        XCTAssertEqual(parse(#"{"format":"1","exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[]}"#), "damaged")
        XCTAssertEqual(parse(#"{"format":true,"exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[]}"#), "damaged")
        XCTAssertEqual(parse(#"{"format":1,"exportedAt":"yesterday","folders":[],"entries":[]}"#), "damaged")
        XCTAssertEqual(parse(#"{"format":1,"exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[\#(item),\#(item)]}"#), "damaged")
        XCTAssertEqual(parse(#"{"format":1,"exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[{"id":"\#(entry)","title":"t","account":"","password":"p","notes":"","folderID":"\#(folder)"}]}"#), "damaged")
        XCTAssertEqual(parse(#"{"format":1,"exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[{"id":"\#(entry)","title":"t"}]}"#), "damaged")
        XCTAssertEqual(parse("[]"), "damaged")
    }

    // MARK: Import (docs/export-format.md, section 7)

    func testMergeAddsNewSkipsSameAndMarksDifferentWithoutChangingWhatIsHere() {
        let work = VaultFolder(name: "Work"), home = VaultFolder(name: "Home")
        let same = VaultEntry(title: "Mail", account: "a", password: "p", folderID: work.id)
        let mine = VaultEntry(title: "Bank", password: "mine")
        var notebook = Notebook()
        notebook.vault = Vault(folders: [work], entries: [same, mine])
        let before = notebook.vault
        var theirs = mine
        theirs.password = "theirs"
        // In the file the folder has another name under the same identifier, and
        // a second folder has this iPhone's name under another identifier.
        let renamed = VaultFolder(id: work.id, name: "Office")
        let sameName = VaultFolder(name: "Work")
        let file = Vault(folders: [renamed, sameName, home], entries: [same, theirs,
            VaultEntry(title: "Shop", password: "s", folderID: sameName.id),
            VaultEntry(title: "Wifi", password: "w", folderID: home.id)])
        let summary = NotebookImport.merge(file, into: &notebook, marker: " (Imported)")
        XCTAssertEqual(summary, ImportSummary(added: 2, skipped: 1, marked: 1))
        XCTAssertEqual(notebook.vault.folders, [work, home])
        // Two folders of one name in the file, a name this iPhone does not have, stay two.
        var empty = Notebook()
        let twins = [VaultFolder(name: "Twin"), VaultFolder(name: "Twin")]
        _ = NotebookImport.merge(Vault(folders: twins), into: &empty)
        XCTAssertEqual(empty.vault.folders, twins)
        XCTAssertEqual(Array(notebook.vault.entries.prefix(2)), before.entries)
        let marked = notebook.vault.entries.first { $0.title == "Bank (Imported)" }
        XCTAssertEqual(marked?.password, "theirs")
        XCTAssertNotEqual(marked?.id, mine.id)
        XCTAssertEqual(notebook.vault.entries.first { $0.title == "Shop" }?.folderID, work.id)
        XCTAssertEqual(notebook.vault.entries.first { $0.title == "Wifi" }?.folderID, home.id)
        XCTAssertTrue(notebook.recentlyDeleted.isEmpty)
        XCTAssertTrue(notebook.changedSinceExport)
        XCTAssertNoThrow(try notebook.validated())
        // Importing the same file again adds nothing more than the differing entry.
        let again = NotebookImport.merge(file, into: &notebook, marker: " (Imported)")
        XCTAssertEqual(again, ImportSummary(added: 0, skipped: 3, marked: 1))
    }

    func testMergeGivesANewIdentifierToAnEntryThatIsInRecentlyDeleted() {
        let entry = VaultEntry(title: "Mail", password: "p")
        var notebook = Notebook()
        notebook.update(Vault(entries: [entry]))
        notebook.update(Vault())
        XCTAssertEqual(notebook.recentlyDeleted.map(\.id), [entry.id])
        let summary = NotebookImport.merge(Vault(entries: [entry]), into: &notebook)
        XCTAssertEqual(summary, ImportSummary(added: 1))
        XCTAssertEqual(notebook.vault.entries.map(\.title), ["Mail"])
        XCTAssertNotEqual(notebook.vault.entries[0].id, entry.id)
        XCTAssertEqual(notebook.recentlyDeleted.map(\.id), [entry.id])
    }

    func testReplaceMovesEverythingHereToRecentlyDeletedWithoutFolders() {
        let now = Date(timeIntervalSince1970: 4_000_000)
        let work = VaultFolder(name: "Work")
        let kept = VaultEntry(title: "Mail", password: "old", folderID: work.id)
        let only = VaultEntry(title: "Bank", password: "b")
        // Deleted earlier, and the file still has an entry with this identifier.
        let earlier = DeletedEntry(entry: VaultEntry(title: "Shop", password: "newer than the file"), deletedAt: now.addingTimeInterval(-3600))
        var notebook = Notebook()
        notebook.vault = Vault(folders: [work], entries: [kept, only])
        notebook.recentlyDeleted = [earlier]
        var incoming = kept
        incoming.password = "new"
        incoming.folderID = nil
        let file = Vault(folders: [VaultFolder(name: "Home")], entries: [incoming, VaultEntry(id: earlier.id, title: "Shop", password: "s")])
        let summary = NotebookImport.replace(file, in: &notebook, now: now)
        XCTAssertEqual(summary, ImportSummary(added: 2))
        XCTAssertEqual(notebook.vault, file)
        XCTAssertEqual(notebook.recentlyDeleted.map(\.entry.title).sorted(), ["Bank", "Mail", "Shop"])
        let survivor = notebook.recentlyDeleted.first { $0.entry.title == "Shop" }
        XCTAssertEqual(survivor?.entry.password, "newer than the file")
        XCTAssertEqual(survivor?.deletedAt, earlier.deletedAt)
        XCTAssertNotEqual(survivor?.id, earlier.id)
        XCTAssertTrue(notebook.recentlyDeleted.filter { $0.entry.title != "Shop" }.allSatisfy { $0.entry.folderID == nil && $0.deletedAt == now })
        XCTAssertEqual(notebook.recentlyDeleted.first { $0.entry.title == "Mail" }?.entry.password, "old")
        XCTAssertNotEqual(notebook.recentlyDeleted.first { $0.entry.title == "Mail" }?.id, kept.id)
        XCTAssertEqual(notebook.recentlyDeleted.first { $0.entry.title == "Bank" }?.id, only.id)
        XCTAssertNoThrow(try notebook.validated())
    }
}
