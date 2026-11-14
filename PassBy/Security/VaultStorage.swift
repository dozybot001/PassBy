import CryptoKit
import Foundation

/// The notebook file on this iPhone. iOS encrypts it while the phone is locked
/// (complete file protection); PassBy adds no key of its own, so the file moves
/// with iCloud Backup, encrypted computer backups and Quick Start.
struct NotebookStore {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("notebook.json", isDirectory: false) }
    var previousURL: URL { directory.appendingPathComponent("notebook.previous.json", isDirectory: false) }
    var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path) || FileManager.default.fileExists(atPath: previousURL.path)
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.root
    }

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PassBy", isDirectory: true)
    }

    /// An empty notebook when nothing was saved yet. When a file exists but
    /// cannot be read, the copy written before it is used; when neither reads,
    /// this throws and nothing is overwritten.
    func load() throws -> Notebook {
        guard exists else { return Notebook() }
        for url in [fileURL, previousURL] {
            if let data = try? Data(contentsOf: url),
               let notebook = try? JSONDecoder().decode(Notebook.self, from: data).validated() {
                return notebook
            }
        }
        if let data = try? Data(contentsOf: fileURL),
           let version = try? JSONDecoder().decode(FileVersion.self, from: data),
           version.fileVersion > Notebook.fileVersion { throw VaultError.unsupportedVersion }
        throw VaultError.invalidData
    }

    private struct FileVersion: Decodable { let fileVersion: Int }

    func save(_ notebook: Notebook) throws {
        do {
            let data = try JSONEncoder().encode(notebook.validated())
            let files = FileManager.default
            try files.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            // Keep the last good file beside the new one.
            if let current = try? Data(contentsOf: fileURL),
               (try? JSONDecoder().decode(Notebook.self, from: current).validated()) != nil {
                try current.write(to: previousURL, options: [.atomic, .completeFileProtection])
            }
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.storageFailed
        }
    }
}

// MARK: - Notebooks left by PassBy 1.x

/// What 1.x kept on the iPhone: an AES-GCM file per iCloud identity, with its
/// key in the Keychain. 2.0 only reads them. It never changes or deletes them.
struct LegacyState: Decodable, Equatable {
    var current: Vault
    var draft: VaultEntry?
    var recentlyDeleted: [DeletedEntry]

    init(current: Vault, draft: VaultEntry? = nil, recentlyDeleted: [DeletedEntry] = []) {
        self.current = current
        self.draft = draft
        self.recentlyDeleted = recentlyDeleted
    }

    private enum CodingKeys: String, CodingKey { case current, draft, recentlyDeleted }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        current = try values.decode(Vault.self, forKey: .current)
        draft = try values.decodeIfPresent(VaultEntry.self, forKey: .draft)
        recentlyDeleted = try values.decodeIfPresent([DeletedEntry].self, forKey: .recentlyDeleted) ?? []
    }
}

struct LegacyNotebook: Equatable {
    /// The folder name: "local" or the hash of an iCloud user record identifier.
    /// The Keychain account of its key ends with the same name.
    let name: String
    let fileURL: URL

    /// Every 1.x notebook in the app's container, found by folder, not by sign-in.
    static func all(root: URL = NotebookStore.root) -> [LegacyNotebook] {
        let files = FileManager.default
        let folders = (try? files.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        return folders.compactMap { url -> LegacyNotebook? in
            let name = url.lastPathComponent
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  name == "local" || (name.count == 64 && name.allSatisfy { $0.isHexDigit }) else { return nil }
            let file = url.appendingPathComponent("notebook.passby", isDirectory: false)
            return files.fileExists(atPath: file.path) ? LegacyNotebook(name: name, fileURL: file) : nil
        }.sorted { $0.name < $1.name }
    }

    func open(key: SymmetricKey) throws -> LegacyState {
        do {
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: fileURL))
            let plaintext = try AES.GCM.open(box, using: key, authenticating: Data("PassBy.local-state.v1".utf8))
            let state = try JSONDecoder().decode(LegacyState.self, from: plaintext)
            _ = try state.current.validated()
            return state
        } catch { throw VaultError.invalidData }
    }
}

struct MigrationSummary: Equatable {
    var entries = 0
    var drafts: [String] = []
}

enum Migration {
    /// Carries 1.x notebooks into the 2.0 notebook. The notebook changes only
    /// when every entry, folder and recently deleted entry of every book is in
    /// it afterwards; otherwise this throws and nothing is changed.
    static func carry(_ books: [(name: String, state: LegacyState)], into notebook: inout Notebook,
                      draftMarker: String = L(" (Unsaved draft)"), now: Date = Date()) throws -> MigrationSummary {
        var next = notebook
        var summary = MigrationSummary()
        for book in books {
            // Entries that are the same in two books are kept once; different ones are all kept.
            _ = NotebookImport.merge(book.state.current, into: &next, marker: "", now: now)
            for item in book.state.recentlyDeleted where !next.recentlyDeleted.contains(where: { same($0.entry, item.entry) }) {
                let taken = next.vault.entries.contains { $0.id == item.id } || next.recentlyDeleted.contains { $0.id == item.id }
                next.recentlyDeleted.append(DeletedEntry(
                    entry: taken ? item.entry.copied(folderID: nil) : item.entry.keeping(folderID: nil),
                    deletedAt: item.deletedAt))
            }
            if let draft = book.state.draft {
                let folder = folderName(draft.folderID, in: book.state.current).flatMap { name in
                    next.vault.folders.first { $0.name == name }?.id
                }
                var copy = draft.copied(suffix: draftMarker, folderID: folder)
                if draft.title.isEmpty { copy.title = draftMarker.trimmingCharacters(in: .whitespaces) }
                var vault = next.vault
                vault.entries.append(copy)
                next.update(vault, now: now)
                summary.drafts.append(copy.title)
            }
            summary.entries += book.state.current.entries.count
        }
        for book in books {
            let state = book.state
            let complete = state.current.folders.allSatisfy { folder in next.vault.folders.contains { $0.name == folder.name } }
                && state.current.entries.allSatisfy { entry in
                    next.vault.entries.contains {
                        same($0, entry) && folderName($0.folderID, in: next.vault) == folderName(entry.folderID, in: state.current)
                    }
                }
                && state.recentlyDeleted.allSatisfy { item in
                    next.recentlyDeleted.contains { same($0.entry, item.entry) }
                        || now.timeIntervalSince(item.deletedAt) >= Notebook.deletedLifetime
                        || next.vault.entries.contains { $0.id == item.id }
                }
            guard complete else { throw VaultError.invalidData }
        }
        next.migratedLegacy = Array(Set(next.migratedLegacy).union(books.map(\.name))).sorted()
        _ = try next.validated()
        notebook = next
        return summary
    }

    private static func same(_ a: VaultEntry, _ b: VaultEntry) -> Bool {
        a.title == b.title && a.account == b.account && a.password == b.password && a.notes == b.notes
    }

    private static func folderName(_ id: UUID?, in vault: Vault) -> String? {
        id.flatMap { id in vault.folders.first { $0.id == id }?.name }
    }
}
