import XCTest
@testable import PassBy

/// AI grouping as docs/android.md 9.2 describes it; the cases follow the Android tests.
final class AiGroupingTests: XCTestCase {
    private let work = VaultFolder(name: "工作")
    private lazy var mail = VaultEntry(title: "gmail", account: "ACCOUNT-alex@example.com", password: "PASSWORD-s3cret", notes: "NOTES-recovery codes", folderID: work.id)
    private let bank = VaultEntry(title: "招行", account: "ACCOUNT-6222", password: "PASSWORD-123456", notes: "NOTES-card pin")
    private let odd = VaultEntry(title: "x", account: "ACCOUNT-odd", password: "PASSWORD-odd", notes: "NOTES-odd")
    private lazy var vault = Vault(folders: [work], entries: [mail, bank, odd])

    private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func response(_ content: String) throws -> String {
        let root: [String: Any] = ["choices": [["message": ["content": content]]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }

    private func event(_ text: String) throws -> String {
        let root: [String: Any] = ["choices": [["delta": ["content": text]]]]
        return "data: " + String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }

    private func assertUnusable<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", line: UInt = #line) {
        XCTAssertThrowsError(try expression(), message, line: line) { XCTAssertTrue($0 is AiGrouping.UnusableAnswer, line: line) }
    }

    // MARK: The request

    func testTheRequestHoldsTitlesAndFolderNamesAndNothingElseFromTheNotebook() {
        // The one way the app builds a request.
        let body = AiGrouping.draft(vault: vault, model: "model-x").body
        for entry in vault.entries {
            XCTAssertTrue(body.contains(entry.title))
            XCTAssertFalse(body.contains(entry.account))
            XCTAssertFalse(body.contains(entry.password))
            XCTAssertFalse(body.contains(entry.notes))
            XCTAssertFalse(body.localizedCaseInsensitiveContains(entry.id.uuidString))
        }
        XCTAssertFalse(body.contains("ACCOUNT-"))
        XCTAssertFalse(body.contains("PASSWORD-"))
        XCTAssertFalse(body.contains("NOTES-"))
        XCTAssertFalse(body.localizedCaseInsensitiveContains(work.id.uuidString))
        XCTAssertTrue(body.contains("工作"))
    }

    func testTheRequestIsWhatTheDocumentSays() throws {
        let body = AiGrouping.request(titles: ["a \"b\"", "c"], folders: ["F"], model: "m")
        let root = try json(body)
        XCTAssertEqual(Set(root.keys), ["model", "messages", "temperature", "stream"])
        XCTAssertEqual(root["model"] as? String, "m")
        XCTAssertEqual(root["stream"] as? Bool, true)
        XCTAssertEqual(root["temperature"] as? Int, 0)
        let messages = try XCTUnwrap(root["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0], ["role": "system", "content": AiGrouping.systemPrompt])
        XCTAssertEqual(messages[1]["role"], "user")
        // The members come in the agreed order, in the body and in the user message.
        XCTAssertEqual(messages[1]["content"], #"{"folders":["F"],"titles":[{"n":1,"title":"a \"b\""},{"n":2,"title":"c"}]}"#)
        XCTAssertTrue(body.hasPrefix(#"{"model":"m","messages":[{"role":"system","content":"You sort"#))
        XCTAssertTrue(body.contains(#"},{"role":"user","content":"{\"folders\":[\"F\"],"#))
        XCTAssertTrue(body.hasSuffix(#"}],"temperature":0,"stream":true}"#))
    }

    func testTextIsEscapedTheWayJsonStringifyDoesIt() throws {
        let odd = "tab\t back\\slash \u{01} 斜/杠 🔑"
        let body = AiGrouping.request(titles: [odd], folders: [], model: "m")
        XCTAssertTrue(body.contains(#"tab\\t back\\\\slash \\u0001 斜/杠 🔑"#))
        let input = try json(try XCTUnwrap((try json(body)["messages"] as? [[String: String]])?[1]["content"]))
        XCTAssertEqual((input["titles"] as? [[String: Any]])?.first?["title"] as? String, odd)
    }

    /// The prompt has to be the same on both platforms, character for character.
    func testThePromptIsTheOneInTheAndroidSource() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("android/app/src/main/kotlin/cn/tenonai/apps/passby/core/AiGrouping.kt")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("no Android source") }
        let start = try XCTUnwrap(source.range(of: "const val SYSTEM_PROMPT ="))
        let end = try XCTUnwrap(source.range(of: "\n\n", range: start.upperBound..<source.endIndex))
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        let block = String(source[start.upperBound..<end.lowerBound])
        let prompt = literal.matches(in: block, range: NSRange(block.startIndex..., in: block)).map { match in
            String(block[Range(match.range(at: 1), in: block)!])
                .replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n")
        }.joined()
        XCTAssertFalse(prompt.contains("\\"))
        XCTAssertEqual(AiGrouping.systemPrompt, prompt)
    }

    func testBlankTitlesAreNotSentAndAtMostFiveHundredGo() {
        var many = Vault()
        many.entries = (1...AiGrouping.maxTitles + 3).map { VaultEntry(title: "t\($0)") } + [VaultEntry(title: "  "), VaultEntry(title: "")]
        let draft = AiGrouping.draft(vault: many, model: "m")
        XCTAssertEqual(draft.titles.count, AiGrouping.maxTitles)
        XCTAssertEqual(draft.titles.first, "t1")
        XCTAssertEqual(draft.titles.last, "t500")
        XCTAssertEqual(draft.entryIDs, many.entries.prefix(AiGrouping.maxTitles).map(\.id))
        XCTAssertEqual(draft.leftOut, 3)
        XCTAssertEqual(draft.blankIDs, many.entries.suffix(2).map(\.id))
        XCTAssertFalse(draft.body.contains("t501"))
    }

    // MARK: The answer

    func testAnAnswerIsReadByNumber() throws {
        let answer = #"{"items":[{"n":2,"folder":"银行","title":"招商银行","unclear":false},{"n":1,"folder":"工作","title":"Gmail","unclear":false},{"n":3,"folder":"","title":"x","unclear":true}]}"#
        XCTAssertEqual(try AiGrouping.parse(response(answer), count: 3), [
            AiGrouping.Suggestion(index: 1, folder: "工作", title: "Gmail", unclear: false),
            AiGrouping.Suggestion(index: 2, folder: "银行", title: "招商银行", unclear: false),
            AiGrouping.Suggestion(index: 3, folder: nil, title: "x", unclear: true),
        ])
        // A code fence around the JSON is tolerated.
        XCTAssertEqual(try AiGrouping.parse(response("```json\n\(answer)\n```"), count: 3).count, 3)
    }

    func testWhatWasNotAskedForIsIgnored() throws {
        let long = String(repeating: "长", count: AiGrouping.maxFolderName + 1)
        let answer = """
        {"items":[
            {"n":0,"folder":"a","title":"a"},
            {"n":4,"folder":"a","title":"a"},
            {"n":"1","folder":"a","title":"a"},
            {"n":true,"folder":"a","title":"a"},
            {"n":1.5,"folder":"a","title":"a"},
            "1",
            {"n":1,"folder":"\(long)","title":"ok","extra":{"run":"rm -rf"}},
            {"n":1,"folder":"second","title":"second"},
            {"n":2,"folder":"  a\\u0000\\n b\u{202E} ","title":"\\t","unclear":"true"}
        ],"also":"ignored"}
        """
        XCTAssertEqual(try AiGrouping.parse(response(answer), count: 3), [
            AiGrouping.Suggestion(index: 1, folder: nil, title: "ok", unclear: false),
            AiGrouping.Suggestion(index: 2, folder: "a b", title: nil, unclear: false),
        ])
    }

    func testAnAnswerInAnotherFormIsRefused() throws {
        for bad in ["", "not json", "{}", #"{"choices":[]}"#, #"{"choices":[{"message":{"content":"sorry"}}]}"#,
                    try response(#"{"items":"none"}"#), try response(#"[{"n":1}]"#), try response("null")] {
            assertUnusable(try AiGrouping.parse(bad, count: 3), bad)
        }
    }

    func testCleaningRemovesWhatShouldNotBeShown() {
        XCTAssertEqual(AiGrouping.clean(" a \r\n\t b ", max: 10), "a b")
        XCTAssertEqual(AiGrouping.clean("a\u{07}b", max: 10), "ab")
        XCTAssertEqual(AiGrouping.clean("a\u{202E}b\u{2066}", max: 10), "ab")
        XCTAssertEqual(AiGrouping.clean("a\u{200B}\u{FEFF}b\u{2028}c\u{00A0}d", max: 10), "ab c d")
        XCTAssertNil(AiGrouping.clean(" \n ", max: 10))
        XCTAssertNil(AiGrouping.clean("abcdef", max: 5))
        XCTAssertEqual(AiGrouping.clean("🔑钥匙", max: 3), "🔑钥匙")
        XCTAssertNil(AiGrouping.clean(nil, max: 3))
    }

    // MARK: What is shown, applied and undone

    func testOnlyWhatWouldChangeIsListed() {
        let blank = VaultEntry(title: " ", password: "PASSWORD-blank")
        let all = Vault(folders: [work], entries: [mail, bank, odd, blank])
        let draft = AiGrouping.draft(vault: all, model: "m")
        let rows = AiGrouping.rows(vault: all, draft: draft, suggestions: [
            AiGrouping.Suggestion(index: 1, folder: "工作", title: "gmail", unclear: false),
            AiGrouping.Suggestion(index: 2, folder: "银行", title: "招商银行", unclear: false),
            AiGrouping.Suggestion(index: 3, folder: nil, title: "X", unclear: true),
            AiGrouping.Suggestion(index: 9, folder: "别处", title: nil, unclear: false),
        ], unclearName: "待明确")
        XCTAssertEqual(rows, [
            AiGrouping.Row(entryID: bank.id, oldTitle: "招行", title: "招商银行", oldFolder: nil, folder: "银行", unclear: false),
            AiGrouping.Row(entryID: odd.id, oldTitle: "x", title: nil, oldFolder: nil, folder: "待明确", unclear: true),
            AiGrouping.Row(entryID: blank.id, oldTitle: " ", title: nil, oldFolder: nil, folder: "待明确", unclear: true),
        ])
    }

    func testApplyingRenamesAndMovesAndKeepsEveryEntry() {
        let changes = [
            AiGrouping.Change(entryID: mail.id, title: "Gmail", folder: "工作"),
            AiGrouping.Change(entryID: bank.id, title: "招商银行", folder: "银行"),
            AiGrouping.Change(entryID: odd.id, title: nil, folder: "待明确"),
            AiGrouping.Change(entryID: UUID(), title: "x", folder: "别处"),
        ]
        var fresh = [UUID(), UUID(), UUID()]
        let ids = fresh
        let applied = AiGrouping.apply(vault, changes: changes) { fresh.removeFirst() }
        let after = applied.vault
        XCTAssertEqual(after.entries.map(\.id), vault.entries.map(\.id))
        // Nothing but the title and the folder changes.
        for (old, new) in zip(vault.entries, after.entries) {
            XCTAssertEqual(old.account, new.account)
            XCTAssertEqual(old.password, new.password)
            XCTAssertEqual(old.notes, new.notes)
        }
        XCTAssertEqual(after.entries.map(\.title), ["Gmail", "招商银行", "x"])
        XCTAssertEqual(after.folders, [work, VaultFolder(id: ids[0], name: "银行"), VaultFolder(id: ids[1], name: "待明确")])
        XCTAssertEqual(after.entries.map(\.folderID), [work.id, ids[0], ids[1]])
        XCTAssertEqual(applied.createdFolders, [ids[0], ids[1]])
        XCTAssertEqual(applied.before, vault.entries)
        XCTAssertNoThrow(try after.validated())

        XCTAssertEqual(AiGrouping.undo(after, applied: applied), vault)
    }

    func testAFolderNamedLikeAnExistingOneIsThatFolder() {
        // The same name, composed and decomposed.
        let cafe = VaultFolder(name: "Caf\u{E9}")
        let start = Vault(folders: [cafe], entries: [bank])
        let applied = AiGrouping.apply(start, changes: [AiGrouping.Change(entryID: bank.id, title: nil, folder: "Cafe\u{301}")])
        XCTAssertEqual(applied.vault.folders, [cafe])
        XCTAssertEqual(applied.vault.entries.first?.folderID, cafe.id)
        XCTAssertEqual(applied.createdFolders, [])
    }

    func testApplyingNothingChangesNothing() {
        XCTAssertEqual(AiGrouping.apply(vault, changes: []), AiGrouping.Applied(vault: vault, before: [], createdFolders: []))
        // The same title and the folder it is already in; a blank title is not taken.
        let same = AiGrouping.apply(vault, changes: [AiGrouping.Change(entryID: mail.id, title: "gmail", folder: "工作"),
                                                     AiGrouping.Change(entryID: bank.id, title: "  ", folder: nil)])
        XCTAssertEqual(same, AiGrouping.Applied(vault: vault, before: [], createdFolders: []))
    }

    func testUndoingLeavesLaterChangesAlone() {
        let applied = AiGrouping.apply(vault, changes: [AiGrouping.Change(entryID: bank.id, title: "招商银行", folder: "银行")])
        let made = applied.createdFolders[0]
        // Since then another entry was put in the new folder and the changed one was deleted.
        var later = applied.vault
        later.save(odd.keeping(folderID: made))
        later.entries.removeAll { $0.id == bank.id }
        let undone = AiGrouping.undo(later, applied: applied)
        XCTAssertEqual(undone.folders, [work, VaultFolder(id: made, name: "银行")])
        XCTAssertEqual(undone.entries, later.entries)
    }

    @MainActor
    func testTheSessionAppliesAndUndoesInOneSaveEach() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotebookStore(directory: root)
        var notebook = Notebook()
        notebook.update(vault)
        try store.save(notebook)
        let suite = "passby-ai-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "gateEnabled")
        defaults.set(true, forKey: "noLockNoticeShown")
        let session = VaultSession(store: store, defaults: defaults)
        await session.unlock()
        XCTAssertEqual(session.vault, vault)

        let applied = try XCTUnwrap(session.applyAiSuggestions([AiGrouping.Change(entryID: bank.id, title: "招商银行", folder: "银行")]))
        XCTAssertEqual(applied.before, [bank])
        XCTAssertEqual(session.vault.entries.map(\.title), ["gmail", "招商银行", "x"])
        XCTAssertEqual(session.vault.folders.map(\.name), ["工作", "银行"])
        XCTAssertEqual(try store.load().vault, session.vault)
        XCTAssertTrue(session.recentlyDeleted.isEmpty)

        XCTAssertTrue(session.undoAiSuggestions(applied))
        XCTAssertEqual(session.vault, vault)
        XCTAssertEqual(try store.load().vault, vault)
        XCTAssertTrue(session.recentlyDeleted.isEmpty)
    }

    // MARK: The address and the key

    func testOnlyAnHttpsAddressIsAccepted() throws {
        XCTAssertEqual(AiGrouping.endpoint(" https://api.deepseek.com/chat/completions "),
                       AiGrouping.Endpoint(url: "https://api.deepseek.com/chat/completions", host: "api.deepseek.com", port: 443))
        let other = try XCTUnwrap(AiGrouping.endpoint("https://API.Example.com:8443/v1/chat/completions"))
        XCTAssertEqual(other.host, "api.example.com")
        // The same host on another port is another place as far as a saved key goes.
        XCTAssertEqual(other.authority, "api.example.com:8443")
        XCTAssertEqual(AiGrouping.endpoint("https://api.example.com/v1")?.authority, "api.example.com:443")
        XCTAssertEqual(AiGrouping.endpoint("HTTPS://api.example.com/v1?a=b")?.authority, "api.example.com:443")
        for bad in ["", "api.deepseek.com", "http://api.deepseek.com/chat", "ftp://a.b/c", "https://", "https:///c", "https://user:pw@a.b/c",
                    "https://user@a.b/c", "https://a.b/c#x", "https://a.b/c#", "https://a b/c", "https://a.b/c d", "file:///etc/hosts",
                    "https://a.b:0/c", "https://a.b:65536/c", "https://a.b:x/c", "https://例子.com/c", "https://a.b/c\nd"] {
            XCTAssertNil(AiGrouping.endpoint(bad), bad)
        }
        XCTAssertEqual(AiGrouping.endpoint(AiGrouping.deepSeekEndpoint)?.url, AiGrouping.deepSeekEndpoint)
    }

    func testAnApiKeyHoldsOnlyVisibleAscii() {
        XCTAssertEqual(AiGrouping.apiKey("  sk-abc_123.XYZ~\n"), "sk-abc_123.XYZ~")
        XCTAssertNotNil(AiGrouping.apiKey(String(repeating: "k", count: AiGrouping.maxKeyLength)))
        for bad in ["", "   ", "sk-abc\ndef", "sk-abc def", "sk-abc\tdef", "sk-密钥", "sk-abc\u{00}", "sk-abc\u{E9}",
                    String(repeating: "k", count: AiGrouping.maxKeyLength + 1)] {
            XCTAssertNil(AiGrouping.apiKey(bad), bad)
        }
    }

    // MARK: A streamed answer

    func testAStreamedAnswerIsPutTogetherFromItsEventsAndCountedAsItArrives() throws {
        var reader = AiGrouping.StreamReader()
        try reader.line(": keep-alive")
        try reader.line("")
        try reader.line(#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#)
        try reader.line(#"data: {"choices":[{"delta":{"reasoning_content":"thinking \"n\":"}}]}"#)
        XCTAssertEqual(reader.received, 0)
        XCTAssertEqual(reader.items, 0)
        try reader.line(event(#"{"items":[{"n":1,"folder":"Work","#))
        XCTAssertEqual(reader.items, 1)
        try reader.line(event(#""title":"Mail","unclear":false},{"n": 2,"unclear":true}]}"#))
        XCTAssertEqual(reader.items, 2)
        XCTAssertFalse(reader.done)
        try reader.line("data: not json")
        try reader.line("data: [DONE]")
        XCTAssertTrue(reader.done)
        try reader.line(event("ignored after the end"))
        let suggestions = try AiGrouping.parseContent(reader.content(), count: 2)
        XCTAssertEqual(suggestions.map(\.folder), ["Work", nil])
        XCTAssertEqual(suggestions.map(\.unclear), [false, true])
    }

    func testAProviderThatIgnoresStreamAndAnswersWithOneDocumentIsStillRead() throws {
        var reader = AiGrouping.StreamReader()
        let whole = #"{"choices":[{"message":{"content":"{\"items\":[{\"n\":1,\"folder\":\"Home\"}]}"}}]}"#
        // Line breaks between members, as a pretty-printing server sends them.
        for line in whole.replacingOccurrences(of: #"{"choices":"#, with: "{\n\"choices\":\n").components(separatedBy: "\n") {
            try reader.line(line)
        }
        XCTAssertEqual(try AiGrouping.parseContent(reader.content(), count: 1).first?.folder, "Home")
    }

    func testAnEmptyOrOversizedStreamIsRefused() throws {
        assertUnusable(try AiGrouping.StreamReader().content())
        var done = AiGrouping.StreamReader()
        try done.line("data: [DONE]")
        assertUnusable(try done.content())
        var small = AiGrouping.StreamReader(maxChars: 10)
        try small.line(#"data: {"choices":[{"delta":{"content":"1234567890"}}]}"#)
        assertUnusable(try small.line(#"data: {"choices":[{"delta":{"content":"1"}}]}"#))
        var plain = AiGrouping.StreamReader(maxChars: 10)
        assertUnusable(try plain.line(String(repeating: "x", count: 41)))
    }

    func testALineWithNoEndIsRefusedOnceItPassesTheLimitWithoutReadingTheRest() throws {
        var endless = AiGrouping.LineReader(maxLine: 1000)
        var fed = 0
        assertUnusable(try { while true { fed += 1; _ = try endless.feed(UInt8(ascii: "x")) } }())
        XCTAssertEqual(fed, 1001)

        var reader = AiGrouping.LineReader(maxLine: 100)
        var lines: [String] = []
        for byte in Array("data: one\r\n\ndata: 二".utf8) {
            if let line = try reader.feed(byte) { lines.append(line) }
        }
        XCTAssertEqual(lines, ["data: one", ""])
        XCTAssertEqual(reader.finish(), "data: 二")
        XCTAssertNil(reader.finish())
        // A line of exactly the limit passes; the limit starts again with each line.
        var exact = AiGrouping.LineReader(maxLine: 3)
        for _ in 1...2 {
            for byte in Array("abc".utf8) { XCTAssertNil(try exact.feed(byte)) }
            XCTAssertEqual(try exact.feed(0x0A), "abc")
        }
    }

    func testSuggestionsAreCountedOnceEvenWhenANumberArrivesInTwoPieces() throws {
        var reader = AiGrouping.StreamReader()
        try reader.line(event(#"{"items":[{"n"#))
        XCTAssertEqual(reader.items, 0)
        try reader.line(event(#"":1},{"n":2},"#))
        XCTAssertEqual(reader.items, 2)
        XCTAssertEqual(reader.items, 2)
        try reader.line(event(#"{"n" : 3},{"name":4},{""n":5}]}"#))
        XCTAssertEqual(reader.items, 4)
    }

    // MARK: Settings and the key

    /// Stands in for the Keychain.
    private final class MemoryStore: AiSecretStore, @unchecked Sendable {
        var items: [String: Data] = [:]
        var failing = false
        func read(_ name: String) -> Data? { items[name] }
        func write(_ name: String, _ data: Data) -> Bool {
            if failing { return false }
            items[name] = data
            return true
        }
        func remove(_ name: String) { items[name] = nil }
    }

    func testTheFeatureStartsOffAndTurningItOffRemovesEverything() {
        let store = MemoryStore()
        let settings = AiSettings(store: store)
        XCTAssertNil(settings.load())
        XCTAssertFalse(settings.hasKey)

        let config = AiSettings.Config(endpoint: AiGrouping.deepSeekEndpoint, model: AiGrouping.deepSeekModel)
        XCTAssertTrue(settings.save(config))
        XCTAssertEqual(settings.load(), config)
        XCTAssertTrue(settings.saveKey("sk-test-only", host: "api.deepseek.com:443"))
        XCTAssertTrue(settings.hasKey)
        XCTAssertEqual(store.items.count, 2)

        settings.turnOff()
        XCTAssertNil(settings.load())
        XCTAssertFalse(settings.hasKey)
        XCTAssertNil(settings.key(host: "api.deepseek.com:443"))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testAKeyIsReadOnlyForTheHostAndPortItWasSavedFor() {
        let settings = AiSettings(store: MemoryStore())
        settings.save(AiSettings.Config(endpoint: "https://api.example.com/v1/chat/completions", model: "m"))
        settings.saveKey("sk-test-only", host: "api.example.com:443")
        XCTAssertEqual(settings.key(host: "api.example.com:443"), "sk-test-only")
        XCTAssertNil(settings.key(host: "api.example.com:8443"))
        XCTAssertNil(settings.key(host: "other.example.com:443"))

        // Another path or model on the same host and port keeps the key.
        settings.save(AiSettings.Config(endpoint: "https://API.example.com:443/v2/chat/completions", model: "m2"))
        XCTAssertEqual(settings.key(host: "api.example.com:443"), "sk-test-only")
        // Another port, another host, or an address that is not accepted: the key goes at once.
        for next in ["https://api.example.com:8443/v1", "https://other.example.com/v1", "http://api.example.com/v1"] {
            settings.saveKey("sk-test-only", host: "api.example.com:443")
            settings.save(AiSettings.Config(endpoint: next, model: "m"))
            XCTAssertFalse(settings.hasKey, next)
            XCTAssertNil(settings.key(host: "api.example.com:443"), next)
        }
        settings.saveKey("sk-test-only", host: "api.example.com:443")
        settings.removeKey()
        XCTAssertFalse(settings.hasKey)
    }

    func testWhatCannotBeSavedIsReported() {
        let store = MemoryStore()
        store.failing = true
        let settings = AiSettings(store: store)
        XCTAssertFalse(settings.save(AiSettings.Config(endpoint: AiGrouping.deepSeekEndpoint, model: "m")))
        XCTAssertFalse(settings.saveKey("sk-test-only", host: "api.deepseek.com:443"))
        XCTAssertNil(settings.load())
    }

    /// Each of these stops before a connection is made.
    func testNothingIsSentWhileOffOrWithoutAnAddressOrAKey() async {
        let settings = AiSettings(store: MemoryStore())
        let approved = AiClient.Approved(body: "{}")
        func problem() async -> AiClient.Problem? {
            do {
                _ = try await AiClient.send(settings: settings, approved: approved)
                return nil
            } catch { return (error as? AiClient.Failure)?.problem }
        }
        var result = await problem()
        XCTAssertEqual(result, .off)
        settings.save(AiSettings.Config(endpoint: "http://api.example.com/v1", model: "m"))
        result = await problem()
        XCTAssertEqual(result, .address)
        settings.save(AiSettings.Config(endpoint: "https://api.example.com/v1", model: "m"))
        result = await problem()
        XCTAssertEqual(result, .noKey)
        // A key saved for another port is not used.
        settings.saveKey("sk-test-only", host: "api.example.com:8443")
        result = await problem()
        XCTAssertEqual(result, .noKey)
        // A key that could not go into a header is not used either.
        settings.saveKey("sk-test only", host: "api.example.com:443")
        result = await problem()
        XCTAssertEqual(result, .noKey)
    }

    @MainActor
    func testAFailureIsShownInOurOwnWords() {
        XCTAssertNil(AiModel.text(AiClient.Failure(.cancelled)))
        XCTAssertEqual(AiModel.text(AiClient.Failure(.status, status: 401)), String(format: L("The provider refused this API key (status %d). Check the key and your balance."), 401))
        XCTAssertEqual(AiModel.text(AiClient.Failure(.status, status: 500)), String(format: L("The provider returned an error (status %d). Check the endpoint and the model name."), 500))
        XCTAssertEqual(AiModel.text(AiClient.Failure(.redirect, status: 302))?.contains("302"), true)
        XCTAssertEqual(AiClient.userAgent, "PassBy-iOS/" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))
    }
}
