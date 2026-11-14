import XCTest
@testable import PassBy

final class PasswordGeneratorTests: XCTestCase {
    func testEveryEnabledTypeIsPresentAtEverySupportedLength() throws {
        for length in Array(8...24) + [25, 64, 128, 256, 4096] {
            var options = PasswordOptions()
            options.length = length
            let generated = try PasswordGenerator.generate(options: options)
            XCTAssertEqual(generated.count, length)
            for alphabet in options.alphabets { XCTAssertTrue(generated.contains { alphabet.contains($0) }) }
        }
    }

    func testOnlySelectedTypesAreGenerated() throws {
        var options = PasswordOptions()
        options.lowercase = false; options.uppercase = false; options.symbols = false
        XCTAssertTrue(try PasswordGenerator.generate(options: options).allSatisfy { "0123456789".contains($0) })
        options.digits = false
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options))
        options.lowercase = true; options.length = 7
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options))
        options.length = 4097
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options))
    }

    func testDraftIsKeptInTheNotebookFileAndLeftOutOfExports() throws {
        let draft = VaultEntry(password: "draft-secret-unique", notes: "unfinished")
        var notebook = Notebook()
        notebook.draft = draft
        let store = NotebookStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(notebook)
        XCTAssertEqual(try store.load().draft, draft)
        XCTAssertTrue(notebook.vault.entries.isEmpty)
        let code = ExportFormat.newCode()
        XCTAssertTrue(try ExportFormat.open(ExportFormat.export(notebook.vault, typed: code), typed: code).entries.isEmpty)
    }
}
