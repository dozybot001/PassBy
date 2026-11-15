import CryptoKit
import XCTest
@testable import PassBy

/// Every vector in docs/sync-vectors.json, which each platform passes so that two devices arrive at
/// the same notebook, and how the notebook keeps the marks a sync needs.
final class SyncTests: XCTestCase {
    private func vectors() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/sync-vectors.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func data(_ value: Any?) throws -> Data { try JSONSerialization.data(withJSONObject: try XCTUnwrap(value)) }
    private func hex(_ text: String) -> Data {
        Data(stride(from: 0, to: text.count, by: 2).map { UInt8(text.dropFirst($0).prefix(2), radix: 16)! })
    }
    private func hex(_ key: SymmetricKey) -> String { key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() } }
    private func summary(_ value: Any?) throws -> SyncSummary { try JSONDecoder().decode(SyncSummary.self, from: data(value)) }

    func testTheFileHasTheExpectedVectors() throws {
        let v = try vectors()
        XCTAssertEqual((v["codes"] as? [Any])?.count, 5)
        XCTAssertEqual(((v["crypto"] as? [String: Any])?["exchanges"] as? [Any])?.count, 3)
        XCTAssertEqual((v["merges"] as? [Any])?.count, 11)
        XCTAssertEqual((v["invalid"] as? [Any])?.count, 6)
    }

    func testCodesAreReadTheSameWay() throws {
        for c in try XCTUnwrap(try vectors()["codes"] as? [[String: Any]]) {
            XCTAssertEqual(SyncCrypto.canonicalCode(c["typed"] as! String), c["code"] as? String, c["typed"] as! String)
        }
        for _ in 0..<50 {
            let code = SyncCrypto.newCode()
            XCTAssertEqual(code.count, 12)
            XCTAssertEqual(SyncCrypto.canonicalCode(SyncCrypto.display(code).lowercased()), code)
        }
    }

    func testKeysAndFramesMatch() throws {
        let c = try XCTUnwrap(try vectors()["crypto"] as? [String: Any])
        let hostNonce = hex(c["hostNonceHex"] as! String), guestNonce = hex(c["guestNonceHex"] as! String)
        let code = try XCTUnwrap(SyncCrypto.canonicalCode(c["typed"] as! String))
        let keys = try SyncCrypto.deriveKeys(code: code, hostNonce: hostNonce, guestNonce: guestNonce, iterations: c["iterations"] as! Int)
        XCTAssertEqual(hex(keys.guestToHost), c["guestToHostKeyHex"] as? String)
        XCTAssertEqual(hex(keys.hostToGuest), c["hostToGuestKeyHex"] as? String)
        for x in try XCTUnwrap(c["exchanges"] as? [[String: Any]]) {
            let counter = UInt64(x["counter"] as! Int)
            let body = try XCTUnwrap(Data(base64Encoded: x["requestBodyBase64"] as! String))
            let request = try SyncCrypto.readRequest(body)
            XCTAssertEqual(request.hostNonce, hostNonce)
            XCTAssertEqual(request.guestNonce, guestNonce)
            XCTAssertEqual(request.counter, counter)
            let plain = try SyncCrypto.open(request.sealed, key: keys.guestToHost, hostNonce: hostNonce, guestNonce: guestNonce, direction: SyncCrypto.guestToHost, counter: counter)
            XCTAssertEqual(String(decoding: plain, as: UTF8.self), x["requestPlaintext"] as? String)
            let sealed = try SyncCrypto.seal(plain, key: keys.guestToHost, hostNonce: hostNonce, guestNonce: guestNonce, direction: SyncCrypto.guestToHost, counter: counter)
            XCTAssertEqual(SyncCrypto.requestBody(hostNonce: hostNonce, guestNonce: guestNonce, counter: counter, sealed: sealed), body)
            let response = try SyncCrypto.readResponse(try XCTUnwrap(Data(base64Encoded: x["responseBodyBase64"] as! String)))
            XCTAssertEqual(response.counter, counter)
            let answer = try SyncCrypto.open(response.sealed, key: keys.hostToGuest, hostNonce: hostNonce, guestNonce: guestNonce, direction: SyncCrypto.hostToGuest, counter: counter)
            XCTAssertEqual(String(decoding: answer, as: UTF8.self), x["responsePlaintext"] as? String)
            if x["hello"] as? Bool == true {
                XCTAssertEqual(counter, 0)
                XCTAssertTrue(SyncCodec.isHello(plain) && SyncCodec.isHello(answer))
                XCTAssertEqual(plain, SyncCodec.hello)
                XCTAssertFalse(SyncCodec.isHello(SyncCodec.request(SyncState())))
            } else {
                XCTAssertEqual(try SyncCodec.readRequest(plain).entries.count, 1)
                XCTAssertEqual(try SyncCodec.readResponse(answer).summary, SyncSummary(added: 0, updated: 0, removed: 0, conflicts: 0))
                XCTAssertFalse(SyncCodec.isHello(plain))
            }
            // A frame must not open under the other direction, another counter or the other key.
            for (key, direction, n) in [(keys.guestToHost, SyncCrypto.hostToGuest, counter), (keys.guestToHost, SyncCrypto.guestToHost, counter + 1), (keys.hostToGuest, SyncCrypto.guestToHost, counter)] {
                XCTAssertThrowsError(try SyncCrypto.open(request.sealed, key: key, hostNonce: hostNonce, guestNonce: guestNonce, direction: direction, counter: n)) {
                    XCTAssertEqual($0 as? SyncError, .refused)
                }
            }
            XCTAssertThrowsError(try SyncCrypto.open(Data(count: 3), key: keys.guestToHost, hostNonce: hostNonce, guestNonce: guestNonce, direction: 0, counter: counter))
        }
    }

    func testMergesMatch() throws {
        for m in try XCTUnwrap(try vectors()["merges"] as? [[String: Any]]) {
            let name = m["name"] as! String
            let host = try SyncCodec.state(data(m["host"])), guest = try SyncCodec.state(data(m["guest"]))
            var ids = m["copyIds"] as! [String]
            let result = try SyncMerge.merge(host: host, guest: guest, marker: m["marker"] as! String) { ids.removeFirst() }
            let expected = try SyncCodec.state(data(m["result"]))
            XCTAssertEqual(result.state, expected, name)
            XCTAssertEqual(result.conflicts, m["conflicts"] as? Int, name)
            XCTAssertEqual(try SyncMerge.summary(before: guest, after: result.state, conflicts: result.conflicts), try summary(m["guestSummary"]), name)
            XCTAssertEqual(try SyncMerge.summary(before: host, after: result.state, conflicts: result.conflicts), try summary(m["hostSummary"]), name)
            // Merging the result with itself changes nothing, and it survives being written and read.
            XCTAssertEqual(try SyncMerge.merge(host: result.state, guest: result.state, marker: "") { XCTFail("no copy expected"); return "" }.state, expected, name)
            XCTAssertEqual(try SyncCodec.readRequest(SyncCodec.request(result.state)), expected, name)
        }
    }

    func testInvalidStatesAreRefused() throws {
        for i in try XCTUnwrap(try vectors()["invalid"] as? [[String: Any]]) {
            XCTAssertThrowsError(try SyncCodec.state(data(i["state"])), i["name"] as! String) { XCTAssertEqual($0 as? SyncError, .invalid) }
        }
    }

    // MARK: The notebook's marks

    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testChangesAreStampedAndDeletionsLeaveTombstones() throws {
        var notebook = Notebook()
        let work = VaultFolder(name: "Work")
        var a = VaultEntry(title: "A", folderID: work.id)
        let b = VaultEntry(title: "B")
        notebook.update(Vault(folders: [work], entries: [a, b]), now: t0)
        let first = Int64(1_000_000)
        XCTAssertEqual(notebook.sync?.entries[a.id.uuidString], SyncStamp(updatedAt: first, dirty: true))
        XCTAssertEqual(notebook.sync?.folders[work.id.uuidString], SyncStamp(updatedAt: first, dirty: true))

        a.title = "A2"
        notebook.update(Vault(folders: [work], entries: [a, b]), now: t0.addingTimeInterval(1))
        XCTAssertEqual(notebook.sync?.entries[a.id.uuidString]?.updatedAt, first + 1000)
        XCTAssertEqual(notebook.sync?.entries[b.id.uuidString]?.updatedAt, first, "an untouched entry keeps its stamp")

        notebook.update(Vault(folders: [work], entries: [a]), now: t0.addingTimeInterval(2))
        XCTAssertNil(notebook.sync?.entries[b.id.uuidString])
        XCTAssertEqual(notebook.sync?.tombstones, [SyncTombstone(id: b.id.uuidString, kind: "entry", deletedAt: first + 2000, dirty: true)])
        XCTAssertEqual(notebook.recentlyDeleted.map(\.id), [b.id])

        notebook.update(Vault(folders: [work], entries: [a, b]), now: t0.addingTimeInterval(3))
        XCTAssertEqual(notebook.sync?.entries[b.id.uuidString], SyncStamp(updatedAt: first + 3000, dirty: true))
        XCTAssertEqual(notebook.sync?.tombstones, [], "putting it back removes the tombstone")

        var vault = notebook.vault
        vault.removeFolder(work.id)
        notebook.update(vault, now: t0.addingTimeInterval(4))
        XCTAssertEqual(notebook.sync?.entries[a.id.uuidString]?.updatedAt, first + 4000, "leaving a deleted folder is a change to the entry")
        XCTAssertEqual(notebook.sync?.tombstones.map(\.kind), ["folder"])

        // Marks survive the file, and a file from before sync reads as changed at an unknown time.
        let saved = try JSONEncoder().encode(notebook)
        XCTAssertEqual(try JSONDecoder().decode(Notebook.self, from: saved), notebook)
        var old = notebook
        old.sync = nil
        let reread = try JSONDecoder().decode(Notebook.self, from: JSONEncoder().encode(old))
        XCTAssertNil(reread.sync)
        XCTAssertEqual(reread.syncState().entries.map(\.updatedAt), [0, 0])
        XCTAssertTrue(reread.syncState().entries.allSatisfy(\.dirty))
    }

    func testTakingASyncedStateKeepsWhatTheOtherDeviceDeletedInRecentlyDeleted() throws {
        var phone = Notebook()
        let a = VaultEntry(title: "A"), b = VaultEntry(title: "B")
        phone.update(Vault(entries: [a, b]), now: t0)
        // Everything on this phone has been synced before.
        for key in phone.sync!.entries.keys { phone.sync!.entries[key]!.dirty = false }
        let folder = UUID().uuidString, c = UUID().uuidString
        let other = SyncState(
            entries: [SyncEntry(id: b.id.uuidString, title: "B", account: "", password: "", notes: "", folderID: nil, updatedAt: 1_000_000, dirty: false),
                      SyncEntry(id: c, title: "C", account: "", password: "", notes: "", folderID: folder, updatedAt: 1_500_000, dirty: true)],
            folders: [SyncFolder(id: folder, name: "Work", updatedAt: 1_500_000, dirty: true)],
            tombstones: [SyncTombstone(id: a.id.uuidString, kind: "entry", deletedAt: 1_600_000, dirty: true)])
        let before = phone.syncState()
        let merged = try SyncMerge.merge(host: before, guest: other, marker: " (Conflict copy)")
        try phone.takeSynced(merged.state, now: t0.addingTimeInterval(900))

        XCTAssertEqual(phone.vault.entries.map(\.title), ["B", "C"])
        XCTAssertEqual(phone.vault.folders.map(\.name), ["Work"])
        XCTAssertEqual(phone.recentlyDeleted.map(\.id), [a.id], "the deleted entry can still be put back")
        XCTAssertFalse(phone.syncState().entries.contains(where: \.dirty) || phone.syncState().folders.contains(where: \.dirty) || phone.syncState().tombstones.contains(where: \.dirty))
        XCTAssertEqual(try SyncMerge.summary(before: before, after: merged.state, conflicts: merged.conflicts), SyncSummary(added: 1, updated: 0, removed: 1, conflicts: 0))
        // A second sync straight away changes nothing.
        let again = phone
        try phone.takeSynced(try SyncMerge.merge(host: phone.syncState(), guest: merged.state, marker: "").state, now: t0.addingTimeInterval(950))
        XCTAssertEqual(phone.vault, again.vault)
        XCTAssertEqual(phone.sync, again.sync)
        // Putting the entry back is a change the next sync carries to the other device.
        var vault = phone.vault
        vault.entries.append(a)
        phone.update(vault, now: t0.addingTimeInterval(1000))
        XCTAssertEqual(phone.sync?.entries[a.id.uuidString], SyncStamp(updatedAt: 2_000_000, dirty: true))
        XCTAssertEqual(phone.sync?.tombstones, [])
    }
}
