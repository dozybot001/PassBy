import Foundation

struct DeletedEntry: Codable, Equatable, Identifiable {
    var entry: VaultEntry
    var deletedAt: Date
    var id: UUID { entry.id }
}

struct LocalVaultState: Codable, Equatable {
    static let deletedLifetime: TimeInterval = 30 * 24 * 60 * 60

    var current: Vault
    var base: Vault
    var recoveryConfirmed: Bool = true
    var draft: VaultEntry? = nil
    /// Only in this device's encrypted state, like drafts; never synced.
    var recentlyDeleted: [DeletedEntry] = []

    /// Keeps entries that left `current`, whether deleted here or by sync.
    mutating func keepDeleted(from previous: Vault, now: Date = Date()) {
        let remaining = Set(current.entries.map(\.id))
        let removed = previous.entries.filter { !remaining.contains($0.id) }
        let removedIDs = Set(removed.map(\.id))
        recentlyDeleted.removeAll { removedIDs.contains($0.id) }
        recentlyDeleted += removed.map { DeletedEntry(entry: $0, deletedAt: now) }
        pruneDeleted(now: now)
    }

    /// Drops expired copies and any entry that is back in the notebook.
    mutating func pruneDeleted(now: Date = Date()) {
        let present = Set(current.entries.map(\.id))
        recentlyDeleted.removeAll {
            present.contains($0.id) || now.timeIntervalSince($0.deletedAt) >= Self.deletedLifetime
        }
    }

    func integratingCloud(_ remote: Vault?, restoringMissingNotebook: Bool = false) throws -> MergeResult {
        guard remote != nil || base == Vault() || restoringMissingNotebook else {
            throw CloudError.notebookChanged
        }
        // A confirmed restore is an initial upload, not a remote deletion of
        // every previously synced item. Existing remote books use normal merge.
        return VaultMerge.merge(base: remote == nil ? Vault() : base,
            local: current, remote: remote ?? Vault())
    }
}

extension LocalVaultState {
    // States saved before Recently Deleted have no list.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        current = try values.decode(Vault.self, forKey: .current)
        base = try values.decode(Vault.self, forKey: .base)
        recoveryConfirmed = try values.decode(Bool.self, forKey: .recoveryConfirmed)
        draft = try values.decodeIfPresent(VaultEntry.self, forKey: .draft)
        recentlyDeleted = try values.decodeIfPresent([DeletedEntry].self, forKey: .recentlyDeleted) ?? []
    }
}

struct MergeResult {
    var vault: Vault
    var conflictCount: Int
}

enum VaultMerge {
    static func merge(base: Vault, local: Vault, remote: Vault) -> MergeResult {
        let baseItems = Dictionary(uniqueKeysWithValues: base.entries.map { ($0.id, $0) })
        let localItems = Dictionary(uniqueKeysWithValues: local.entries.map { ($0.id, $0) })
        let remoteItems = Dictionary(uniqueKeysWithValues: remote.entries.map { ($0.id, $0) })
        var result = Vault()
        var conflicts = 0
        let ids = Set(baseItems.keys).union(localItems.keys).union(remoteItems.keys)
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            let original = baseItems[id], ours = localItems[id], theirs = remoteItems[id]
            if ours == original {
                if let theirs { result.entries.append(theirs) }
            } else if theirs == original || ours == theirs {
                if let ours { result.entries.append(ours) }
            } else if let ours, let theirs {
                result.entries.append(theirs)
                result.entries.append(VaultEntry(title: ours.title + L(" (Conflict copy)"),
                    account: ours.account, password: ours.password, notes: ours.notes,
                    folderID: ours.folderID))
                conflicts += 1
            } else if let surviving = ours ?? theirs {
                // An edit wins over a concurrent deletion to prevent secret loss.
                result.entries.append(surviving)
                conflicts += 1
            }
        }
        let b = Dictionary(uniqueKeysWithValues: base.folders.map { ($0.id, $0) })
        let l = Dictionary(uniqueKeysWithValues: local.folders.map { ($0.id, $0) })
        let r = Dictionary(uniqueKeysWithValues: remote.folders.map { ($0.id, $0) })
        for id in Set(b.keys).union(l.keys).union(r.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
            let value = l[id] == b[id] ? r[id] : l[id]
            if let value { result.folders.append(value) }
        }
        let folderIDs = Set(result.folders.map(\.id))
        for index in result.entries.indices {
            if let id = result.entries[index].folderID, !folderIDs.contains(id) {
                result.entries[index].folderID = nil
            }
        }
        return MergeResult(vault: result, conflictCount: conflicts)
    }
}
