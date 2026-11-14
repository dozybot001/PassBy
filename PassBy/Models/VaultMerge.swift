import Foundation

/// What an export file holds once decrypted (docs/export-format.md, section 4).
struct ExportPayload: Codable, Equatable {
    var format = 1
    var exportedAt: String
    var folders: [VaultFolder]
    var entries: [VaultEntry]

    init(vault: Vault, now: Date = Date()) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        exportedAt = formatter.string(from: now)
        folders = vault.folders
        entries = vault.entries
    }

    var vault: Vault { Vault(folders: folders, entries: entries) }
}

struct ImportSummary: Equatable {
    var added = 0
    var skipped = 0
    var marked = 0
}

/// Import rules shared with Android (docs/export-format.md, section 7).
enum NotebookImport {
    /// Adds the file to the notebook. Nothing already here is changed or removed.
    static func merge(_ file: Vault, into notebook: inout Notebook, marker: String = L(" (Imported)"),
                      now: Date = Date()) -> ImportSummary {
        var next = notebook.vault
        var summary = ImportSummary()
        // Same identifier: this iPhone's name stays. Same name: use this iPhone's folder.
        var folderMap: [UUID: UUID] = [:]
        for folder in file.folders {
            if next.folders.contains(where: { $0.id == folder.id }) {
                folderMap[folder.id] = folder.id
            } else if let same = next.folders.first(where: { sameName($0.name, folder.name) }) {
                folderMap[folder.id] = same.id
            } else {
                next.folders.append(folder)
                folderMap[folder.id] = folder.id
            }
        }
        let deleted = Set(notebook.recentlyDeleted.map(\.id))
        for incoming in file.entries {
            let folderID = incoming.folderID.flatMap { folderMap[$0] }
            let value = incoming.keeping(folderID: folderID)
            if let mine = next.entries.first(where: { $0.id == value.id }) {
                if mine == value {
                    summary.skipped += 1
                } else {
                    next.entries.append(value.copied(suffix: marker, folderID: folderID))
                    summary.marked += 1
                }
            } else {
                // A new identifier keeps a later restore from Recently Deleted apart.
                next.entries.append(deleted.contains(value.id) ? value.copied(folderID: folderID) : value)
                summary.added += 1
            }
        }
        notebook.update(next, now: now)
        return summary
    }

    /// Takes the file's folders and entries. Everything that was here moves to
    /// Recently Deleted for 30 days, without folders.
    static func replace(_ file: Vault, in notebook: inout Notebook, now: Date = Date()) -> ImportSummary {
        let incoming = Set(file.entries.map(\.id))
        let previous = notebook.vault.entries.map { entry in
            // An identifier the file also uses stays with the file's entry.
            DeletedEntry(entry: incoming.contains(entry.id) ? entry.copied(folderID: nil) : entry.keeping(folderID: nil),
                         deletedAt: now)
        }
        let moved = Set(previous.map(\.id))
        notebook.recentlyDeleted.removeAll { moved.contains($0.id) || incoming.contains($0.id) }
        if notebook.vault != file { notebook.changedSinceExport = true }
        notebook.vault = file
        notebook.recentlyDeleted += previous
        notebook.pruneDeleted(now: now)
        return ImportSummary(added: file.entries.count)
    }

    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.precomposedStringWithCanonicalMapping.unicodeScalars.elementsEqual(
            b.precomposedStringWithCanonicalMapping.unicodeScalars)
    }
}
