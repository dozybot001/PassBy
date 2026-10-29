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

enum VaultError: Error, LocalizedError, Equatable {
    case unsupportedVersion, invalidData, missingKey, invalidKey
    case faceIDRequired, authenticationFailed, storageFailed, captureActive

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return L("This notebook was saved by a newer version of PassBy. Update the app to open it.")
        case .invalidData: return L("The notebook could not be verified. Your saved file has been kept unchanged.")
        case .missingKey, .invalidKey: return LB("The key for this notebook is unavailable. A change to Face ID or the device passcode may make local data unrecoverable.")
        case .faceIDRequired: return LB("Set up Face ID and a device passcode in iPhone Settings to use PassBy.")
        case .authenticationFailed: return LB("Face ID did not unlock the notebook. Please try again.")
        case .storageFailed: return L("Your changes could not be saved. Check available storage and try again.")
        case .captureActive: return L("Stop screen recording or mirroring before unlocking your notebook.")
        }
    }
}

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
