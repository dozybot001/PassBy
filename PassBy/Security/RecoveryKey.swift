import CryptoKit
import Foundation

/// The recovery key of a PassBy 1.x notebook: its 256-bit key with a checksum.
/// 2.0 has no recovery key; this only opens an old notebook during migration.
enum RecoveryKey {
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
        guard Data(data.suffix(2)) == Data(SHA256.hash(data: raw).prefix(2)) else { throw RecoveryError.invalid }
        return SymmetricKey(data: raw)
    }
}

enum RecoveryError: Error, LocalizedError {
    case invalid, wrongNotebook
    var errorDescription: String? {
        switch self {
        case .invalid: return L("Check the recovery key. Its length or checksum is incorrect.")
        case .wrongNotebook: return L("This recovery key does not open the earlier notebook on this iPhone.")
        }
    }
}
