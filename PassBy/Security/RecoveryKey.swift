import CryptoKit
import Foundation

/// A random 256-bit key, not a human password. The checksum detects transcription
/// errors; the key is never sent to CloudKit or stored in app preferences.
enum RecoveryKey {
    static func format(_ key: SymmetricKey) -> String {
        let data = key.withUnsafeBytes { Data($0) }
        let checksum = Data(SHA256.hash(data: data)).prefix(2)
        let text = (data + checksum).map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: text.count, by: 4).map { offset in
            let start = text.index(text.startIndex, offsetBy: offset)
            let end = text.index(start, offsetBy: min(4, text.count - offset))
            return String(text[start..<end])
        }.joined(separator: "-")
    }

    static func parse(_ text: String) throws -> SymmetricKey {
        let normalized = text.filter { !$0.isWhitespace && $0 != "-" }.uppercased()
        guard normalized.count == 68 else { throw RecoveryError.invalid }
        var data = Data()
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let end = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<end], radix: 16) else { throw RecoveryError.invalid }
            data.append(byte)
            index = end
        }
        let raw = Data(data.prefix(32))
        guard Data(data.suffix(2)) == Data(SHA256.hash(data: raw).prefix(2)) else {
            throw RecoveryError.invalid
        }
        return SymmetricKey(data: raw)
    }
}

enum RecoveryError: Error, LocalizedError {
    case invalid, wrongNotebook
    var errorDescription: String? {
        switch self {
        case .invalid: return L("Check the recovery key. Its length or checksum is incorrect.")
        case .wrongNotebook: return L("This recovery key does not unlock your iCloud notebook.")
        }
    }
}
