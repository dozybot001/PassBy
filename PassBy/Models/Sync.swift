import CryptoKit
import Foundation

// LAN sync (docs/sync.md): what the notebook keeps for it, the state two devices exchange, the
// merge both arrive at, and the pairing code, keys and frames. scripts/sync-format.mjs is the
// reference; docs/sync-vectors.json is passed by every platform.

/// When an entry or folder last changed, and whether it changed since this iPhone last synced.
struct SyncStamp: Codable, Equatable {
    var updatedAt: Int64
    var dirty: Bool

    /// For items saved before the app kept stamps: no known time, and treated as changed.
    static let unknown = SyncStamp(updatedAt: 0, dirty: true)
}

/// A record that an entry or folder was deleted, so the deletion can reach the other device.
struct SyncTombstone: Codable, Equatable {
    static let entry = "entry"
    static let folder = "folder"

    var id: String
    var kind: String
    var deletedAt: Int64
    var dirty: Bool
}

/// What the notebook keeps for sync next to its entries and folders. Keys are upper-case UUIDs.
struct SyncMarks: Codable, Equatable {
    static let tombstoneLifetime: Int64 = 400 * 24 * 60 * 60 * 1000

    var entries: [String: SyncStamp] = [:]
    var folders: [String: SyncStamp] = [:]
    var tombstones: [SyncTombstone] = []

    /// The marks after the notebook went from `old` to `new`: changed and new items are stamped
    /// `now` and marked as changed; items that are gone leave a tombstone.
    func marked(from old: Vault, to new: Vault, now: Int64) -> SyncMarks {
        let oldEntries = Dictionary(uniqueKeysWithValues: old.entries.map { ($0.id, $0) })
        let oldFolders = Dictionary(uniqueKeysWithValues: old.folders.map { ($0.id, $0) })
        var next = SyncMarks()
        for entry in new.entries {
            next.entries[entry.id.uuidString] = oldEntries[entry.id] == entry
                ? entries[entry.id.uuidString] ?? .unknown : SyncStamp(updatedAt: now, dirty: true)
        }
        for folder in new.folders {
            next.folders[folder.id.uuidString] = oldFolders[folder.id] == folder
                ? folders[folder.id.uuidString] ?? .unknown : SyncStamp(updatedAt: now, dirty: true)
        }
        func live(_ t: SyncTombstone) -> Bool {
            (t.kind == SyncTombstone.entry ? next.entries : next.folders)[t.id] != nil
        }
        next.tombstones = tombstones.filter { !live($0) && now - $0.deletedAt < Self.tombstoneLifetime }
        let gone = old.entries.map { ($0.id.uuidString, SyncTombstone.entry) } + old.folders.map { ($0.id.uuidString, SyncTombstone.folder) }
        for (id, kind) in gone {
            let candidate = SyncTombstone(id: id, kind: kind, deletedAt: now, dirty: true)
            if !live(candidate), !next.tombstones.contains(where: { $0.id == id && $0.kind == kind }) {
                next.tombstones.append(candidate)
            }
        }
        return next
    }
}

struct SyncEntry: Codable, Equatable {
    var id: String
    var title: String
    var account: String
    var password: String
    var notes: String
    var folderID: String?
    var updatedAt: Int64
    var dirty: Bool

    func sameContent(_ other: SyncEntry) -> Bool {
        title == other.title && account == other.account && password == other.password
            && notes == other.notes && folderID == other.folderID
    }
}

struct SyncFolder: Codable, Equatable {
    var id: String
    var name: String
    var updatedAt: Int64
    var dirty: Bool
}

/// One device's notebook as it is exchanged (docs/sync.md 6.4).
struct SyncState: Codable, Equatable {
    var entries: [SyncEntry] = []
    var folders: [SyncFolder] = []
    var tombstones: [SyncTombstone] = []
}

/// What a sync changed for one device.
struct SyncSummary: Codable, Equatable {
    var added: Int
    var updated: Int
    var removed: Int
    var conflicts: Int
}

enum SyncError: Error, Equatable {
    /// The other side sent something that is not a valid state.
    case invalid
    /// A frame did not open: wrong code, wrong direction or counter, or tampering.
    case refused
}

enum SyncMerge {
    private static let maxTime: Int64 = 9_007_199_254_740_991

    private static func uuid(_ text: String) throws -> String {
        // UUID(uuidString:) accepts exactly the 8-4-4-4-12 form; the length check keeps out anything it pads.
        guard text.utf8.count == 36, let id = UUID(uuidString: text) else { throw SyncError.invalid }
        return id.uuidString
    }

    /// Checks a state and returns it with identifiers in upper case.
    static func validate(_ state: SyncState) throws -> SyncState {
        func time(_ value: Int64) throws { guard (0...maxTime).contains(value) else { throw SyncError.invalid } }
        var out = SyncState()
        for var folder in state.folders {
            folder.id = try uuid(folder.id)
            try time(folder.updatedAt)
            out.folders.append(folder)
        }
        let folderIDs = Set(out.folders.map(\.id))
        for var entry in state.entries {
            entry.id = try uuid(entry.id)
            try time(entry.updatedAt)
            if let folder = entry.folderID {
                entry.folderID = try uuid(folder)
                guard folderIDs.contains(entry.folderID!) else { throw SyncError.invalid }
            }
            out.entries.append(entry)
        }
        for var tombstone in state.tombstones {
            tombstone.id = try uuid(tombstone.id)
            try time(tombstone.deletedAt)
            guard tombstone.kind == SyncTombstone.entry || tombstone.kind == SyncTombstone.folder else { throw SyncError.invalid }
            out.tombstones.append(tombstone)
        }
        for kind in [SyncTombstone.entry, SyncTombstone.folder] {
            let dead = out.tombstones.filter { $0.kind == kind }.map(\.id)
            let live = kind == SyncTombstone.entry ? out.entries.map(\.id) : out.folders.map(\.id)
            guard Set(dead).count == dead.count, Set(live).count == live.count, Set(live).isDisjoint(with: dead) else { throw SyncError.invalid }
        }
        return out
    }

    /// One side's view of an identifier: a live item or a tombstone.
    private enum Side {
        case entry(SyncEntry), folder(SyncFolder), dead(SyncTombstone)

        var live: Bool { if case .dead = self { return false } else { return true } }
        var dirty: Bool {
            switch self {
            case .entry(let e): return e.dirty
            case .folder(let f): return f.dirty
            case .dead(let t): return t.dirty
            }
        }
        var time: Int64 {
            switch self {
            case .entry(let e): return e.updatedAt
            case .folder(let f): return f.updatedAt
            case .dead(let t): return t.deletedAt
            }
        }
    }

    private static func sides(_ state: SyncState, _ kind: String) -> [String: Side] {
        var map: [String: Side] = [:]
        if kind == SyncTombstone.entry { for e in state.entries { map[e.id] = .entry(e) } }
        else { for f in state.folders { map[f.id] = .folder(f) } }
        for t in state.tombstones where t.kind == kind { map[t.id] = .dead(t) }
        return map
    }

    /// Merges the host's and the guest's states. `marker` is appended to the title of a conflict
    /// copy; `freshID` supplies the identifier of each copy, in ascending order of the entry's
    /// identifier. The result has nothing dirty and is sorted by identifier.
    static func merge(host hostState: SyncState, guest guestState: SyncState, marker: String,
                      freshID: () -> String = { UUID().uuidString }) throws -> (state: SyncState, conflicts: Int) {
        let host = try validate(hostState), guest = try validate(guestState)
        var out = SyncState()
        var conflicts = 0
        func keep(_ side: Side, updatedAt: Int64? = nil) {
            switch side {
            case .entry(var e): e.dirty = false; e.updatedAt = updatedAt ?? e.updatedAt; out.entries.append(e)
            case .folder(var f): f.dirty = false; f.updatedAt = updatedAt ?? f.updatedAt; out.folders.append(f)
            case .dead(var t): t.dirty = false; out.tombstones.append(t)
            }
        }
        for kind in [SyncTombstone.folder, SyncTombstone.entry] {
            let h = sides(host, kind), g = sides(guest, kind)
            for id in Set(h.keys).union(g.keys).sorted() {
                guard let a = h[id], let b = g[id] else { keep(h[id] ?? g[id]!); continue }
                let same: Bool
                switch (a, b) {
                case (.entry(let x), .entry(let y)): same = x.sameContent(y)
                case (.folder(let x), .folder(let y)): same = x.name == y.name
                default: same = !a.live && !b.live
                }
                // The later one; the host's when they are equally late.
                let hostIsLater = b.time <= a.time
                let later = hostIsLater ? a : b
                if same {
                    if a.live { keep(a, updatedAt: max(a.time, b.time)) } else { keep(later) }
                } else if a.dirty != b.dirty {
                    keep(a.dirty ? a : b)
                } else if !a.dirty {
                    keep(later)
                } else if a.live && b.live {
                    // Both changed since they last agreed.
                    keep(later)
                    if case .entry(var loser) = hostIsLater ? b : a {
                        loser.id = freshID().uppercased()
                        loser.title += marker
                        loser.dirty = false
                        out.entries.append(loser)
                        conflicts += 1
                    }
                } else if a.live || b.live {
                    keep(a.live ? a : b) // an edit outlives a deletion
                } else {
                    keep(later)
                }
            }
        }
        let folderIDs = Set(out.folders.map(\.id))
        for index in out.entries.indices {
            if let folder = out.entries[index].folderID, !folderIDs.contains(folder) { out.entries[index].folderID = nil }
        }
        out.entries.sort { $0.id < $1.id }
        out.folders.sort { $0.id < $1.id }
        out.tombstones.sort { $0.kind + $0.id < $1.kind + $1.id }
        return (out, conflicts)
    }

    /// What changed for the side that had `before`: entries gained, entries whose content changed, entries lost.
    static func summary(before: SyncState, after: SyncState, conflicts: Int) throws -> SyncSummary {
        let old = Dictionary(uniqueKeysWithValues: try validate(before).entries.map { ($0.id, $0) })
        let now = Dictionary(uniqueKeysWithValues: after.entries.map { ($0.id, $0) })
        let added = now.keys.filter { old[$0] == nil }.count
        let updated = now.filter { id, entry in old[id].map { !$0.sameContent(entry) } ?? false }.count
        let removed = old.keys.filter { now[$0] == nil }.count
        return SyncSummary(added: added - conflicts, updated: updated, removed: removed, conflicts: conflicts)
    }
}

/// The JSON inside the frames (docs/sync.md 6.4).
enum SyncCodec {
    static let hello = Data(#"{"v":1,"hello":true}"#.utf8)

    private struct Request: Codable {
        var v: Int
        var entries: [SyncEntry]
        var folders: [SyncFolder]
        var tombstones: [SyncTombstone]
    }

    private struct Response: Codable {
        var v: Int
        var state: SyncState
        var summary: SyncSummary
    }

    /// True when the opened plaintext is the greeting and nothing else.
    static func isHello(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object.count == 2,
              let version = object["v"] as? NSNumber, let hello = object["hello"] as? NSNumber else { return false }
        return CFGetTypeID(hello) == CFBooleanGetTypeID() && hello.boolValue
            && CFGetTypeID(version) != CFBooleanGetTypeID() && version.doubleValue == 1
    }

    static func request(_ state: SyncState) -> Data {
        (try? JSONEncoder().encode(Request(v: 1, entries: state.entries, folders: state.folders, tombstones: state.tombstones))) ?? Data()
    }

    static func readRequest(_ data: Data) throws -> SyncState {
        guard let request = try? JSONDecoder().decode(Request.self, from: data), request.v == 1 else { throw SyncError.invalid }
        return try SyncMerge.validate(SyncState(entries: request.entries, folders: request.folders, tombstones: request.tombstones))
    }

    static func response(_ state: SyncState, _ summary: SyncSummary) -> Data {
        (try? JSONEncoder().encode(Response(v: 1, state: state, summary: summary))) ?? Data()
    }

    static func readResponse(_ data: Data) throws -> (state: SyncState, summary: SyncSummary) {
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.v == 1,
              [response.summary.added, response.summary.updated, response.summary.removed, response.summary.conflicts].allSatisfy({ $0 >= 0 })
        else { throw SyncError.invalid }
        return (try SyncMerge.validate(response.state), response.summary)
    }

    static func state(_ data: Data) throws -> SyncState {
        guard let state = try? JSONDecoder().decode(SyncState.self, from: data) else { throw SyncError.invalid }
        return try SyncMerge.validate(state)
    }
}

/// The pairing code, the keys and the frames (docs/sync.md 6.3). CommonCrypto and CryptoKit only.
enum SyncCrypto {
    static let iterations = 600_000
    static let nonceLength = 16
    static let tagLength = 16
    static let guestToHost: UInt8 = 0
    static let hostToGuest: UInt8 = 1
    /// Bytes before the sealed part of a request: both nonces and the counter.
    static let requestHeader = nonceLength * 2 + 8
    private static let prefix = Data("PassBy sync v1".utf8)

    struct Keys {
        let guestToHost: SymmetricKey
        let hostToGuest: SymmetricKey
    }

    struct Request {
        let hostNonce: Data
        let guestNonce: Data
        let counter: UInt64
        let sealed: Data
    }

    /// A fresh pairing code: 12 characters, 60 bits.
    static func newCode() -> String { ExportFormat.newCode(length: 12) }

    /// The code as shown, in groups of four.
    static func display(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 4).map { String(code.dropFirst($0).prefix(4)) }.joined(separator: "-")
    }

    /// The 12-character code, or nil. Spaces and dashes are ignored; I, L and O read as 1, 1 and 0.
    static func canonicalCode(_ input: String) -> String? { ExportFormat.canonical(input, length: 12) }

    static func deriveKeys(code: String, hostNonce: Data, guestNonce: Data, iterations: Int = iterations) throws -> Keys {
        guard let master = ExportFormat.pbkdf2(secret: Data(code.utf8), salt: prefix + hostNonce + guestNonce, iterations: iterations) else { throw SyncError.refused }
        let input = SymmetricKey(data: master)
        func key(_ info: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: input, info: Data(info.utf8), outputByteCount: 32)
        }
        return Keys(guestToHost: key("PassBy sync v1 guest to host"), hostToGuest: key("PassBy sync v1 host to guest"))
    }

    private static func counterBytes(_ counter: UInt64) -> Data {
        withUnsafeBytes(of: counter.bigEndian) { Data($0) }
    }

    private static func aad(_ hostNonce: Data, _ guestNonce: Data, _ direction: UInt8, _ counter: UInt64) -> Data {
        prefix + hostNonce + guestNonce + Data([direction]) + counterBytes(counter)
    }

    /// Ciphertext followed by the tag. A key must never seal two frames with the same counter; the
    /// caller counts up from zero within one session, whose keys are bound to fresh nonces.
    static func seal(_ plaintext: Data, key: SymmetricKey, hostNonce: Data, guestNonce: Data, direction: UInt8, counter: UInt64) throws -> Data {
        guard let nonce = try? AES.GCM.Nonce(data: Data(count: 4) + counterBytes(counter)),
              let box = try? AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad(hostNonce, guestNonce, direction, counter))
        else { throw SyncError.refused }
        return box.ciphertext + box.tag
    }

    static func open(_ sealed: Data, key: SymmetricKey, hostNonce: Data, guestNonce: Data, direction: UInt8, counter: UInt64) throws -> Data {
        guard sealed.count >= tagLength,
              let nonce = try? AES.GCM.Nonce(data: Data(count: 4) + counterBytes(counter)),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: sealed.dropLast(tagLength), tag: sealed.suffix(tagLength)),
              let plain = try? AES.GCM.open(box, using: key, authenticating: aad(hostNonce, guestNonce, direction, counter))
        else { throw SyncError.refused }
        return plain
    }

    static func requestBody(hostNonce: Data, guestNonce: Data, counter: UInt64, sealed: Data) -> Data {
        hostNonce + guestNonce + counterBytes(counter) + sealed
    }

    static func responseBody(counter: UInt64, sealed: Data) -> Data { counterBytes(counter) + sealed }

    private static func counter(_ bytes: Data) -> UInt64 { bytes.reduce(0) { $0 << 8 | UInt64($1) } }

    static func readRequest(_ body: Data) throws -> Request {
        guard body.count >= requestHeader + tagLength else { throw SyncError.refused }
        let bytes = Data(body)
        return Request(hostNonce: bytes.prefix(nonceLength), guestNonce: Data(bytes.dropFirst(nonceLength).prefix(nonceLength)),
            counter: counter(Data(bytes.dropFirst(nonceLength * 2).prefix(8))), sealed: Data(bytes.dropFirst(requestHeader)))
    }

    /// The counter and the sealed part of a response.
    static func readResponse(_ body: Data) throws -> (counter: UInt64, sealed: Data) {
        guard body.count >= 8 + tagLength else { throw SyncError.refused }
        let bytes = Data(body)
        return (counter(Data(bytes.prefix(8))), Data(bytes.dropFirst(8)))
    }
}

extension Notebook {
    /// This notebook as it is sent to the other device.
    func syncState() -> SyncState {
        let marks = sync ?? SyncMarks()
        return SyncState(
            entries: vault.entries.map {
                let stamp = marks.entries[$0.id.uuidString] ?? .unknown
                return SyncEntry(id: $0.id.uuidString, title: $0.title, account: $0.account, password: $0.password, notes: $0.notes,
                    folderID: $0.folderID?.uuidString, updatedAt: stamp.updatedAt, dirty: stamp.dirty)
            },
            folders: vault.folders.map {
                let stamp = marks.folders[$0.id.uuidString] ?? .unknown
                return SyncFolder(id: $0.id.uuidString, name: $0.name, updatedAt: stamp.updatedAt, dirty: stamp.dirty)
            },
            tombstones: marks.tombstones)
    }

    /// Takes the merged `state` of a sync. Entries and folders keep their place in the list and new
    /// ones go to the end. An entry the other device deleted moves to Recently Deleted here instead
    /// of vanishing, so it can still be put back for 30 days. The result is not stamped as a change
    /// made on this iPhone.
    mutating func takeSynced(_ state: SyncState, now: Date = Date()) throws {
        let state = try SyncMerge.validate(state)
        func id(_ text: String) throws -> UUID {
            guard let id = UUID(uuidString: text) else { throw SyncError.invalid }
            return id
        }
        var folders: [UUID: VaultFolder] = [:], entries: [UUID: VaultEntry] = [:]
        for f in state.folders { folders[try id(f.id)] = VaultFolder(id: try id(f.id), name: f.name) }
        for e in state.entries {
            entries[try id(e.id)] = VaultEntry(id: try id(e.id), title: e.title, account: e.account, password: e.password,
                notes: e.notes, folderID: try e.folderID.map(id))
        }
        var next = Vault()
        next.folders = vault.folders.compactMap { folders[$0.id] }
            + (try state.folders.map { try id($0.id) }).filter { new in !vault.folders.contains { $0.id == new } }.compactMap { folders[$0] }
        next.entries = vault.entries.compactMap { entries[$0.id] }
            + (try state.entries.map { try id($0.id) }).filter { new in !vault.entries.contains { $0.id == new } }.compactMap { entries[$0] }
        _ = try next.validated()
        update(next, now: now)
        if let folder = draft?.folderID, folders[folder] == nil { draft?.folderID = nil }
        var marks = SyncMarks()
        for e in state.entries { marks.entries[e.id] = SyncStamp(updatedAt: e.updatedAt, dirty: false) }
        for f in state.folders { marks.folders[f.id] = SyncStamp(updatedAt: f.updatedAt, dirty: false) }
        marks.tombstones = state.tombstones.map { var t = $0; t.dirty = false; return t }
        sync = marks
    }
}
