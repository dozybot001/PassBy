import XCTest
@testable import PassBy

/// The listening side turning away what it should, the connecting side keeping the notebook back
/// until the host has proved it holds the code, and the two talking over the loopback interface.
final class SyncTransportTests: XCTestCase {
    private let code = "AB3D9KXMP2QW"
    private let iterations = 1000
    private let authority = "192.168.1.20:52814"
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var hostNotebook = Notebook()

    override func setUp() {
        hostNotebook = Notebook()
        hostNotebook.update(Vault(entries: [VaultEntry(title: "host", password: "h")]), now: clock)
    }

    private func core() -> SyncHostCore {
        SyncHostCore(code: code, authority: authority, iterations: iterations, now: { self.clock }) { guest in
            guard let merged = try? SyncMerge.merge(host: self.hostNotebook.syncState(), guest: guest, marker: " (Conflict copy)"),
                  (try? self.hostNotebook.takeSynced(merged.state, now: self.clock)) != nil,
                  let summary = try? SyncMerge.summary(before: guest, after: merged.state, conflicts: merged.conflicts) else { return nil }
            return (merged.state, summary)
        }
    }

    private func message(_ method: String, _ path: String, body: Data = Data(), host: String? = nil, extra: [String: String] = [:]) -> SyncHTTP.Message {
        var headers = ["host": host ?? authority, "content-length": String(body.count)]
        headers.merge(extra) { $1 }
        return SyncHTTP.Message(start: "\(method) \(path) HTTP/1.1", headers: headers, body: body)
    }

    /// A guest driven by hand, so that single frames can be replayed, reordered and forged.
    private struct Manual {
        let nonce: Data
        let guestNonce = Data(repeating: 7, count: 16)
        let keys: SyncCrypto.Keys

        func frame(_ counter: UInt64, _ plain: Data, direction: UInt8 = SyncCrypto.guestToHost, otherKey: Bool = false) throws -> Data {
            let sealed = try SyncCrypto.seal(plain, key: otherKey ? keys.hostToGuest : keys.guestToHost, hostNonce: nonce, guestNonce: guestNonce, direction: direction, counter: counter)
            return SyncCrypto.requestBody(hostNonce: nonce, guestNonce: guestNonce, counter: counter, sealed: sealed)
        }
    }

    private func manual(_ host: SyncHostCore, code: String? = nil) throws -> Manual {
        let reply = try XCTUnwrap(host.respond(to: message("POST", SyncHTTP.begin)))
        XCTAssertEqual(reply.status, "200 OK")
        return Manual(nonce: reply.body, keys: try SyncCrypto.deriveKeys(code: code ?? self.code, hostNonce: reply.body, guestNonce: Data(repeating: 7, count: 16), iterations: iterations))
    }

    private func status(_ host: SyncHostCore, _ body: Data) -> String? {
        host.respond(to: message("POST", SyncHTTP.exchange, body: body))?.status
    }

    private var emptyState: Data { SyncCodec.request(SyncState()) }

    func testARecordedFrameCannotBeSentAgainAndCountersOnlyGoUp() throws {
        let host = core()
        let g = try manual(host)
        XCTAssertEqual(status(host, try g.frame(0, SyncCodec.hello)), "200 OK")
        XCTAssertEqual(status(host, try g.frame(0, SyncCodec.hello)), "403 Forbidden", "a replayed greeting")
        let third = try g.frame(3, emptyState)
        XCTAssertEqual(status(host, third), "200 OK")
        XCTAssertEqual(status(host, third), "403 Forbidden", "a replayed state")
        XCTAssertEqual(status(host, try g.frame(2, emptyState)), "403 Forbidden", "a counter that goes back")
        XCTAssertEqual(status(host, try g.frame(4, emptyState)), "200 OK")
    }

    func testAFrameForTheOtherDirectionOrWithTheOtherKeyIsRefused() throws {
        let host = core()
        let g = try manual(host)
        XCTAssertEqual(status(host, try g.frame(0, SyncCodec.hello)), "200 OK")
        XCTAssertEqual(status(host, try g.frame(1, emptyState, direction: SyncCrypto.hostToGuest)), "403 Forbidden")
        XCTAssertEqual(status(host, try g.frame(2, emptyState, otherKey: true)), "403 Forbidden")
        XCTAssertEqual(status(host, try g.frame(3, emptyState)), "200 OK")
    }

    func testAStateInPlaceOfTheGreetingAndAGreetingInPlaceOfAStateAreNotTaken() throws {
        let host = core()
        let before = hostNotebook
        let early = try manual(host)
        XCTAssertEqual(status(host, try early.frame(0, emptyState)), "400 Bad Request")
        XCTAssertEqual(status(host, try early.frame(0, SyncCodec.hello)), "403 Forbidden", "its nonce is used up")
        let g = try manual(host)
        XCTAssertEqual(status(host, try g.frame(0, SyncCodec.hello)), "200 OK")
        XCTAssertEqual(status(host, try g.frame(1, SyncCodec.hello)), "400 Bad Request")
        XCTAssertEqual(status(host, try g.frame(2, Data(#"{"v":2,"entries":[],"folders":[],"tombstones":[]}"#.utf8))), "400 Bad Request")
        XCTAssertEqual(status(host, try g.frame(3, Data("not json".utf8))), "400 Bad Request")
        XCTAssertEqual(hostNotebook, before)
    }

    func testTheCodeIsGoodForOneSessionAndFiveWrongCodesAreCounted() throws {
        let host = core()
        let first = try manual(host), waiting = try manual(host)
        XCTAssertEqual(status(host, try first.frame(0, SyncCodec.hello)), "200 OK")
        XCTAssertEqual(host.respond(to: message("POST", SyncHTTP.begin))?.status, "403 Forbidden")
        XCTAssertEqual(status(host, try waiting.frame(0, SyncCodec.hello)), "403 Forbidden")
        XCTAssertEqual(status(host, try first.frame(1, emptyState)), "200 OK", "the session itself carries on")
        for _ in 0..<SyncHostCore.maxFailures + 2 {
            XCTAssertEqual(status(host, try waiting.frame(1, emptyState)), "403 Forbidden")
            XCTAssertEqual(status(host, try first.frame(9, emptyState, otherKey: true)), "403 Forbidden")
        }
        XCTAssertEqual(host.failures, 0, "with the code used up, refused frames no longer count")
        XCTAssertEqual(status(host, try first.frame(20, emptyState)), "200 OK")

        let other = core()
        for attempt in 1...SyncHostCore.maxFailures {
            let wrong = try manual(other, code: "AB3D9KXMP2QX")
            XCTAssertEqual(status(other, try wrong.frame(0, SyncCodec.hello)), "403 Forbidden")
            XCTAssertEqual(other.failures, attempt)
        }
        other.stop()
        XCTAssertEqual(other.respond(to: message("POST", SyncHTTP.begin))?.status, "410 Gone")
    }

    func testOnlyAFewUnusedNoncesAreKeptAndEachExpiresAfterAMinute() throws {
        let host = core()
        let old = try manual(host)
        for _ in 1..<SyncHostCore.maxPending { XCTAssertEqual(host.respond(to: message("POST", SyncHTTP.begin))?.status, "200 OK") }
        XCTAssertEqual(host.respond(to: message("POST", SyncHTTP.begin))?.status, "403 Forbidden")
        clock += SyncHostCore.nonceLifetime
        XCTAssertEqual(status(host, try old.frame(0, SyncCodec.hello)), "403 Forbidden", "an expired nonce")
        XCTAssertEqual(host.respond(to: message("POST", SyncHTTP.begin))?.status, "200 OK", "room again")
        XCTAssertEqual(host.failures, 1, "asking for nonces never counts against the code")
    }

    func testRequestsUnderAnotherNameAreDroppedAndOtherSitesAreTurnedAway() {
        let host = core()
        XCTAssertEqual(host.respond(to: message("OPTIONS", SyncHTTP.exchange, extra: ["origin": SyncHTTP.origin]))?.status, "204 No Content")
        for bad in ["phone.evil.example:52814", "192.168.1.20", "192.168.1.21:52814"] {
            XCTAssertNil(host.respond(to: message("POST", SyncHTTP.begin, host: bad)), bad)
        }
        XCTAssertNil(host.respond(to: SyncHTTP.Message(start: "POST \(SyncHTTP.begin) HTTP/1.1", headers: ["content-length": "0"], body: Data())), "no Host")
        XCTAssertNil(host.respond(to: SyncHTTP.Message(start: "POST \(SyncHTTP.begin) HTTP/1.1", headers: ["host": authority], body: Data())), "no length")
        XCTAssertNil(host.respond(to: SyncHTTP.Message(start: "nonsense", headers: ["host": authority], body: Data())))
        for origin in ["https://evil.example", "http://passby.tenonai.cn", "null"] {
            XCTAssertEqual(host.respond(to: message("POST", SyncHTTP.begin, extra: ["origin": origin]))?.status, "403 Forbidden")
            XCTAssertEqual(host.respond(to: message("OPTIONS", SyncHTTP.begin, extra: ["origin": origin]))?.status, "403 Forbidden")
        }
        for (method, path) in [("GET", "/"), ("PUT", SyncHTTP.begin), ("POST", "/passby-sync/v1/other")] {
            XCTAssertEqual(host.respond(to: message(method, path))?.status, "400 Bad Request")
        }
        XCTAssertEqual(host.respond(to: message("POST", SyncHTTP.begin, body: Data([1])))?.status, "400 Bad Request")
        XCTAssertEqual(host.failures, 0)
    }

    func testMessagesAreReadStrictly() {
        func parse(_ text: String) -> SyncHTTP.Parsed { SyncHTTP.parse(Data(text.utf8)) }
        guard case .complete(let message) = parse("POST /x HTTP/1.1\r\nContent-Length: 3\r\nX-Other:  v \r\n\r\nabcdef") else { return XCTFail("a whole message") }
        XCTAssertEqual(message.body, Data("abc".utf8))
        XCTAssertEqual(message.headers["x-other"], "v")
        XCTAssertEqual(parse("POST /x HTTP/1.1\r\nContent-Length: 3\r\n\r\nab"), .incomplete)
        XCTAssertEqual(parse("POST /x HTTP/1.1\r\n"), .incomplete)
        let bad = ["POST /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n", "POST /x HTTP/1.1\r\nContent-Length: 12abc\r\n\r\n",
            "POST /x HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\na", "POST /x HTTP/1.1\r\nno colon\r\n\r\n",
            "POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n", "POST /x HTTP/1.1\r\nExpect: 100-continue\r\n\r\n",
            "POST /x HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n", "POST /x HTTP/1.1\r\nContent-Length: 123456789\r\n\r\n",
            "POST /x HTTP/1.1\r\n" + String(repeating: "A: b\r\n", count: 33) + "\r\n",
            "GET / HTTP/1.1\r\nX: " + String(repeating: "y", count: 9000) + "\r\n\r\n", String(repeating: "z", count: 9000)]
        for text in bad { XCTAssertEqual(parse(text), .bad, String(text.prefix(50))) }
    }

    func testAddressesMustBePrivateAndWrittenOut() {
        XCTAssertEqual(SyncAddress.parse(" 10.91.92.79:52814 "), SyncAddress(host: "10.91.92.79", port: 52814))
        XCTAssertEqual(SyncAddress.parse("172.16.0.1:1")?.description, "172.16.0.1:1")
        XCTAssertNotNil(SyncAddress.parse("192.168.1.20:65535"))
        for bad in ["8.8.8.8:80", "172.32.0.1:80", "127.0.0.1:80", "192.168.1.20", "192.168.1.20:0", "192.168.1.20:65536", "192.168.1.256:80",
                    "phone.local:80", "http://10.0.0.1:80", "10.0.0.1:80/x", "10.0.0.1:80:1", "１０.0.0.1:80"] {
            XCTAssertNil(SyncAddress.parse(bad), bad)
        }
    }

    func testNothingOfTheNotebookIsSentBeforeTheHostHasAnsweredTheGreeting() async throws {
        // A host that does not hold the code: it hands out a nonce and answers every exchange with noise.
        var seen: [Int] = []
        let guest = SyncGuest(code: code, iterations: iterations) { path, body in
            seen.append(body.count)
            return (200, Data(repeating: 1, count: path == SyncHTTP.begin ? 16 : 60))
        }
        var phone = Notebook()
        phone.update(Vault(entries: [VaultEntry(title: "guest", password: "a-long-secret-that-would-show-in-the-size")]), now: clock)
        do {
            _ = try await guest.exchange(phone.syncState())
            XCTFail("expected the answer to be refused")
        } catch {
            XCTAssertEqual(error as? SyncGuestError, .untrusted)
        }
        XCTAssertEqual(seen, [0, SyncCrypto.requestHeader + SyncCodec.hello.count + SyncCrypto.tagLength])
    }

    /// A port nothing is listening on right now, found by letting the system pick one.
    private func freePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0 }
        }
        try XCTSkipUnless(bound, "no free port")
        return UInt16(bigEndian: address.sin_port)
    }

    func testTwoPhonesEndUpWithTheSameNotebookOverLoopback() async throws {
        let address = SyncAddress(host: "127.0.0.1", port: try freePort())
        let host = try SyncHost(code: code, address: address, iterations: iterations, exchange: { guest in
            guard let merged = try? SyncMerge.merge(host: self.hostNotebook.syncState(), guest: guest, marker: " (Conflict copy)"),
                  (try? self.hostNotebook.takeSynced(merged.state, now: self.clock)) != nil,
                  let summary = try? SyncMerge.summary(before: guest, after: merged.state, conflicts: merged.conflicts) else { return nil }
            return (merged.state, summary)
        }, onStopped: { _ in })
        host.start()
        defer { host.stop() }
        try await Task.sleep(nanoseconds: 300_000_000)

        var phone = Notebook()
        phone.update(Vault(entries: [VaultEntry(title: "guest", password: "g")]), now: clock)
        let guest = SyncGuest(code: code, iterations: iterations) { path, body in try await SyncGuest.send(to: address, path: path, body: body) }
        let result = try await guest.exchange(phone.syncState())
        try phone.takeSynced(result.state, now: clock)
        XCTAssertEqual(result.summary, SyncSummary(added: 1, updated: 0, removed: 0, conflicts: 0))
        XCTAssertEqual(Set(phone.vault.entries.map(\.title)), ["host", "guest"])
        XCTAssertEqual(Set(hostNotebook.vault.entries), Set(phone.vault.entries))
        XCTAssertEqual(hostNotebook.sync, phone.sync)

        // The same session carries a later change.
        var vault = phone.vault
        vault.entries[vault.entries.firstIndex { $0.title == "guest" }!].password = "g2"
        phone.update(vault, now: clock.addingTimeInterval(5))
        let second = try await guest.exchange(phone.syncState())
        XCTAssertEqual(second.summary, SyncSummary(added: 0, updated: 0, removed: 0, conflicts: 0))
        XCTAssertEqual(hostNotebook.vault.entries.first { $0.title == "guest" }?.password, "g2")

        // A wrong code against the same host is refused: the code has been used.
        let late = SyncGuest(code: code, iterations: iterations) { path, body in try await SyncGuest.send(to: address, path: path, body: body) }
        do {
            _ = try await late.exchange(SyncState())
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? SyncGuestError, .wrongCode)
        }
    }

    // The two tests below talk to the reference implementation running on the Mac (scripts/sync-dev-host.mjs
    // and scripts/sync-dev-guest.mjs) with the real key derivation. They are skipped unless the addresses
    // are given: TEST_RUNNER_PASSBY_INTEROP_HOST and TEST_RUNNER_PASSBY_INTEROP_LISTEN on the xcodebuild line.
    private let interopCode = "AB3D9KXMP2QW"

    func testInteropAsGuestOfTheReferenceHost() async throws {
        guard let text = ProcessInfo.processInfo.environment["PASSBY_INTEROP_HOST"], let address = SyncAddress.parse(text) else {
            throw XCTSkip("no reference host")
        }
        var phone = Notebook()
        phone.update(Vault(entries: [VaultEntry(title: "iphone", account: "a@example.com", password: "example-only", notes: "第一行\nsecond")]), now: Date())
        let guest = SyncGuest(address: address, code: interopCode)
        let first = try await guest.exchange(phone.syncState())
        try phone.takeSynced(first.state, now: Date())
        XCTAssertEqual(first.summary.conflicts, 0)
        XCTAssertGreaterThanOrEqual(first.summary.added, 1)
        XCTAssertTrue(phone.vault.entries.contains { $0.title == "iphone" })
        XCTAssertGreaterThanOrEqual(phone.vault.entries.count, 2)
        print("INTEROP guest after first:", phone.vault.entries.map(\.title).sorted(), phone.vault.folders.map(\.name), first.summary)

        var vault = phone.vault
        vault.entries[vault.entries.firstIndex { $0.title == "iphone" }!].password = "example-changed"
        phone.update(vault, now: Date())
        let second = try await guest.exchange(phone.syncState())
        try phone.takeSynced(second.state, now: Date())
        XCTAssertEqual(second.summary, SyncSummary(added: 0, updated: 0, removed: 0, conflicts: 0))
        print("INTEROP guest after second:", second.summary)
    }

    func testInteropAsHostOfTheReferenceGuest() async throws {
        guard let text = ProcessInfo.processInfo.environment["PASSBY_INTEROP_LISTEN"], let address = SyncAddress.parse(text) else {
            throw XCTSkip("no address to listen on")
        }
        var notebook = Notebook()
        notebook.update(Vault(entries: [VaultEntry(title: "iphone host", password: "example-only")]), now: Date())
        let lock = NSLock()
        var exchanges = 0
        let host = try SyncHost(code: interopCode, address: address, exchange: { guest in
            lock.lock(); defer { lock.unlock() }
            guard let merged = try? SyncMerge.merge(host: notebook.syncState(), guest: guest, marker: " (Conflict copy)"),
                  (try? notebook.takeSynced(merged.state, now: Date())) != nil,
                  let summary = try? SyncMerge.summary(before: guest, after: merged.state, conflicts: merged.conflicts) else { return nil }
            exchanges += 1
            return (merged.state, summary)
        }, onStopped: { _ in })
        func read() -> (Int, [VaultEntry]) { lock.lock(); defer { lock.unlock() }; return (exchanges, notebook.vault.entries) }
        host.start()
        defer { host.stop() }
        print("INTEROP host listening on", address)
        for _ in 0..<240 {
            try await Task.sleep(nanoseconds: 500_000_000)
            if read().0 >= 2 { break }
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let (count, entries) = read()
        XCTAssertEqual(count, 2)
        print("INTEROP host ended with:", entries.map { "\($0.title)|\($0.notes)" }.sorted())
        XCTAssertTrue(entries.contains { $0.title == "iphone host" })
        XCTAssertEqual(entries.first { $0.title == "q" }?.notes, "edited on the Mac 1")
    }
}

extension VaultEntry: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
