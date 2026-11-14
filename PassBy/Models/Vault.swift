import Foundation

struct VaultFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct VaultEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var account: String
    var password: String
    var notes: String
    var folderID: UUID?

    init(id: UUID = UUID(), title: String = "", account: String = "",
         password: String = "", notes: String = "", folderID: UUID? = nil) {
        self.id = id
        self.title = title
        self.account = account
        self.password = password
        self.notes = notes
        self.folderID = folderID
    }

    /// The same entry under a new identifier, optionally with a title suffix.
    func copied(suffix: String = "", folderID: UUID?) -> VaultEntry {
        VaultEntry(title: title + suffix, account: account, password: password, notes: notes, folderID: folderID)
    }
}

struct Vault: Codable, Equatable {
    var schemaVersion = 1
    var folders: [VaultFolder] = []
    var entries: [VaultEntry] = []

    mutating func save(_ entry: VaultEntry) {
        var value = entry
        if let folderID = value.folderID, !folders.contains(where: { $0.id == folderID }) {
            value.folderID = nil
        }
        if let index = entries.firstIndex(where: { $0.id == value.id }) {
            entries[index] = value
        } else {
            entries.append(value)
        }
    }

    mutating func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for index in entries.indices where entries[index].folderID == id {
            entries[index].folderID = nil
        }
    }

    func validated() throws -> Vault {
        guard schemaVersion == 1 else { throw VaultError.unsupportedVersion }
        guard Set(folders.map(\.id)).count == folders.count,
              Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ entry in
                  entry.folderID.map { id in folders.contains { $0.id == id } } ?? true
              }) else { throw VaultError.invalidData }
        return self
    }
}

struct DeletedEntry: Codable, Equatable, Identifiable {
    var entry: VaultEntry
    var deletedAt: Date
    var id: UUID { entry.id }
}

/// Everything PassBy keeps, in one file on this iPhone. iOS encrypts the file
/// while the phone is locked; it travels with the phone's own backups.
struct Notebook: Codable, Equatable {
    static let fileVersion = 2
    static let deletedLifetime: TimeInterval = 30 * 24 * 60 * 60
    static let exportReminderInterval: TimeInterval = 30 * 24 * 60 * 60

    var fileVersion = Notebook.fileVersion
    var vault = Vault()
    var draft: VaultEntry?
    var recentlyDeleted: [DeletedEntry] = []
    var lastExportAt: Date?
    var changedSinceExport = false
    var exportReminderDismissedAt: Date?
    /// Folder names of 1.x notebooks already carried into this file. The old
    /// encrypted files and keys stay where they are and are never deleted.
    var migratedLegacy: [String] = []

    /// Replaces the entries and folders, keeping what left in Recently Deleted.
    mutating func update(_ next: Vault, now: Date = Date()) {
        let remaining = Set(next.entries.map(\.id))
        let removed = vault.entries.filter { !remaining.contains($0.id) }
        let removedIDs = Set(removed.map(\.id))
        recentlyDeleted.removeAll { removedIDs.contains($0.id) }
        recentlyDeleted += removed.map { DeletedEntry(entry: $0, deletedAt: now) }
        if next != vault { changedSinceExport = true }
        vault = next
        pruneDeleted(now: now)
    }

    /// Drops expired copies and any entry that is back in the notebook.
    mutating func pruneDeleted(now: Date = Date()) {
        let present = Set(vault.entries.map(\.id))
        recentlyDeleted.removeAll {
            present.contains($0.id) || now.timeIntervalSince($0.deletedAt) >= Self.deletedLifetime
        }
    }

    /// Never exported, or not for 30 days with changes since; shown once per 30 days.
    func needsExportReminder(now: Date = Date()) -> Bool {
        guard !vault.entries.isEmpty else { return false }
        if let dismissed = exportReminderDismissedAt,
           now.timeIntervalSince(dismissed) < Self.exportReminderInterval { return false }
        guard let last = lastExportAt else { return true }
        return changedSinceExport && now.timeIntervalSince(last) >= Self.exportReminderInterval
    }

    func validated() throws -> Notebook {
        guard fileVersion == Self.fileVersion else { throw VaultError.unsupportedVersion }
        _ = try vault.validated()
        return self
    }
}

extension VaultEntry {
    func keeping(folderID: UUID?) -> VaultEntry {
        var value = self
        value.folderID = folderID
        return value
    }
}

enum VaultError: Error, LocalizedError, Equatable {
    case unsupportedVersion, invalidData, authenticationFailed, storageFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return L("This notebook was saved by a newer version of PassBy. Update the app to open it.")
        case .invalidData: return L("The notebook could not be verified. Your saved file has been kept unchanged.")
        case .authenticationFailed: return L("The notebook was not unlocked. Please try again.")
        case .storageFailed: return L("Your changes could not be saved. Check available storage and try again.")
        }
    }
}

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
