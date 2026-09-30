import CloudKit
import CryptoKit
import Foundation

@MainActor
final class CloudNotebook {
    static let containerIdentifier = "iCloud.cn.tenonai.apps.passby"
    private let container = CKContainer(identifier: containerIdentifier)
    private let recordID = CKRecord.ID(recordName: "notebook-v1")
    private var database: CKDatabase { container.privateCloudDatabase }

    func ownerID() async throws -> String {
        guard try await container.accountStatus() == .available else { throw CloudError.accountRequired }
        let id = try await container.userRecordID()
        return SHA256.hash(data: Data(id.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func fetch() async throws -> CKRecord? {
        do { return try await database.record(for: recordID) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }

    func ciphertext(in record: CKRecord) throws -> Data {
        guard record["format"] as? Int == 1,
              let asset = record["ciphertext"] as? CKAsset,
              let file = asset.fileURL else { throw VaultError.invalidData }
        return try Data(contentsOf: file)
    }

    func save(_ data: Data, replacing record: CKRecord?) async throws -> CKRecord {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("PassBySync")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        let file = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: file) }
        let outgoing = record ?? CKRecord(recordType: "Notebook", recordID: recordID)
        outgoing["format"] = 1 as NSNumber
        outgoing["ciphertext"] = CKAsset(fileURL: file)
        // CKDatabase.save respects the record's change tag. A stale version fails
        // with serverRecordChanged and is fetched and merged again by the caller.
        return try await database.save(outgoing)
    }
}

enum CloudError: Error, LocalizedError {
    case accountRequired, unavailable, notebookChanged
    var errorDescription: String? {
        switch self {
        case .accountRequired: return L("Sign in to iCloud in iPhone Settings to use PassBy.")
        case .unavailable: return L("iCloud could not be reached. Check your connection and try again.")
        case .notebookChanged: return L("The notebook changed on another device. Please try again.")
        }
    }
}
