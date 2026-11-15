import CommonCrypto
import CryptoKit
import Foundation

enum ExportError: Error, LocalizedError, Equatable {
    case notExport, update, damaged, wrongCode

    var errorDescription: String? {
        switch self {
        case .notExport: return L("This is not a PassBy export file.")
        case .update: return L("This file was made by a newer version. Update PassBy to open it.")
        case .damaged: return L("The file is damaged or was changed.")
        case .wrongCode: return L("The export code or passphrase is not right.")
        }
    }
}

enum PassphraseProblem: String {
    case surroundingSpace, looksLikeCode, tooShort

    var message: String {
        switch self {
        case .surroundingSpace: return L("Remove the spaces at the start or end.")
        case .looksLikeCode: return L("This looks like an export code. Choose a different passphrase.")
        case .tooShort: return L("Use at least 12 characters.")
        }
    }
}

/// The encrypted export file shared by iPhone, Android and the web
/// (docs/export-format.md). Only the system's own cryptography is used.
enum ExportFormat {
    static let headerLength = 58
    static let iterations = 600_000
    static let iterationRange = 100_000...10_000_000
    private static let magic = Data("PASSBYEX".utf8)
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let spaces: Set<UInt32> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000, 0x2001,
        0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
        0x3000, 0xFEFF]
    private static let dashes: Set<UInt32> = [0x2D, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015]

    // MARK: What the person types

    /// The 20-character export code, or nil when the input is not one.
    static func canonicalCode(_ input: String) -> String? { canonical(input, length: 20) }

    /// A code of `length` characters in the export alphabet, or nil. Sync's pairing code is read the same way.
    static func canonical(_ input: String, length: Int) -> String? {
        var out = ""
        for scalar in input.unicodeScalars {
            if spaces.contains(scalar.value) || dashes.contains(scalar.value) { continue }
            var character = Character(scalar)
            if (0x61...0x7A).contains(scalar.value) { character = Character(UnicodeScalar(scalar.value - 32)!) }
            if character == "I" || character == "L" { character = "1" } else if character == "O" { character = "0" }
            guard alphabet.contains(character) else { return nil }
            out.append(character)
        }
        return out.count == length ? out : nil
    }

    private static func trimmed(_ input: String) -> String {
        var scalars = Array(input.unicodeScalars)
        while let first = scalars.first, spaces.contains(first.value) { scalars.removeFirst() }
        while let last = scalars.last, spaces.contains(last.value) { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// The bytes that go into PBKDF2 for an export code or a passphrase.
    static func secretBytes(_ input: String) -> Data {
        if let code = canonicalCode(input) { return Data(code.utf8) }
        return Data(trimmed(input).precomposedStringWithCanonicalMapping.utf8)
    }

    /// Rules for a passphrase set when exporting; nil when it is acceptable.
    static func passphraseProblem(_ input: String) -> PassphraseProblem? {
        if trimmed(input) != input { return .surroundingSpace }
        if canonicalCode(input) != nil { return .looksLikeCode }
        if input.precomposedStringWithCanonicalMapping.unicodeScalars.count < 12 { return .tooShort }
        return nil
    }

    /// A new export code, shown as four groups of five.
    /// `length` random characters of the export alphabet, without separators.
    static func newCode(length: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
    }

    static func newCode() -> String {
        var generator = SystemRandomNumberGenerator()
        let characters = (0..<20).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] }
        return stride(from: 0, to: 20, by: 5).map { String(characters[$0..<$0 + 5]) }.joined(separator: "-")
    }

    static func fileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "PassBy-\(formatter.string(from: now)).passby"
    }

    // MARK: Keys

    struct Keys {
        let encrypt: SymmetricKey
        let check: Data
    }

    /// PBKDF2-HMAC-SHA256 to 32 bytes, or nil when the system refuses the parameters.
    static func pbkdf2(secret: Data, salt: Data, iterations: Int) -> Data? {
        var master = [UInt8](repeating: 0, count: 32)
        let status = secret.withUnsafeBytes { password in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    password.bindMemory(to: Int8.self).baseAddress, secret.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &master, master.count)
            }
        }
        return status == kCCSuccess ? Data(master) : nil
    }

    static func deriveKeys(secret: Data, salt: Data, iterations: Int) throws -> Keys {
        guard let master = pbkdf2(secret: secret, salt: salt, iterations: iterations) else { throw ExportError.wrongCode }
        let input = SymmetricKey(data: master)
        let encrypt = HKDF<SHA256>.deriveKey(inputKeyMaterial: input,
            info: Data("PassBy export v1 encrypt".utf8), outputByteCount: 32)
        let checkKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: input,
            info: Data("PassBy export v1 check".utf8), outputByteCount: 32)
        let check = Data(HMAC<SHA256>.authenticationCode(for: Data("PassBy export key check".utf8), using: checkKey)).prefix(16)
        return Keys(encrypt: encrypt, check: Data(check))
    }

    // MARK: Writing

    static func random(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    static func seal(plaintext: Data, secret: Data, salt: Data = random(16), nonce: Data = random(12),
                     iterations: Int = ExportFormat.iterations) throws -> Data {
        guard !secret.isEmpty, salt.count == 16, nonce.count == 12 else { throw ExportError.damaged }
        let keys = try deriveKeys(secret: secret, salt: salt, iterations: iterations)
        var header = magic
        header.append(contentsOf: [1, 1])
        header.append(contentsOf: withUnsafeBytes(of: UInt32(iterations).bigEndian) { Array($0) })
        header.append(salt)
        header.append(nonce)
        header.append(keys.check)
        let box = try AES.GCM.seal(plaintext, using: keys.encrypt, nonce: AES.GCM.Nonce(data: nonce),
                                   authenticating: header)
        return header + box.ciphertext + box.tag
    }

    /// Encrypts the notebook's folders and entries. Recently Deleted is not exported.
    static func export(_ vault: Vault, typed: String, now: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try seal(plaintext: encoder.encode(ExportPayload(vault: vault, now: now)), secret: secretBytes(typed))
    }

    // MARK: Reading

    /// Checks that need no code, so a wrong file is refused before asking for one.
    static func inspect(_ file: Data) throws {
        guard file.count >= headerLength + 16, file.prefix(8) == magic else { throw ExportError.notExport }
        let bytes = [UInt8](file.prefix(headerLength))
        guard bytes[8] == 1, bytes[9] == 1 else { throw ExportError.update }
        guard iterationRange.contains(iterationCount(bytes)) else { throw ExportError.damaged }
    }

    private static func iterationCount(_ header: [UInt8]) -> Int {
        header[10..<14].reduce(0) { $0 << 8 | Int($1) }
    }

    static func decrypt(_ file: Data, typed: String) throws -> Data {
        try inspect(file)
        let bytes = [UInt8](file)
        let header = Data(bytes[0..<headerLength])
        let secret = secretBytes(typed)
        guard !secret.isEmpty else { throw ExportError.wrongCode }
        let keys = try deriveKeys(secret: secret, salt: Data(bytes[14..<30]), iterations: iterationCount(bytes))
        // Constant-time comparison of the passphrase check value.
        let stored = bytes[42..<58]
        guard zip(keys.check, stored).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 else { throw ExportError.wrongCode }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Data(bytes[30..<42])),
                ciphertext: Data(bytes[headerLength..<bytes.count - 16]), tag: Data(bytes[(bytes.count - 16)...]))
            return try AES.GCM.open(box, using: keys.encrypt, authenticating: header)
        } catch { throw ExportError.damaged }
    }

    static func open(_ file: Data, typed: String) throws -> ExportPayload {
        try parse(decrypt(file, typed: typed))
    }

    static func parse(_ plaintext: Data) throws -> ExportPayload {
        guard let object = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              let number = object["format"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(number.intValue) else { throw ExportError.damaged }
        guard number.intValue == 1 else { throw ExportError.update }
        guard let payload = try? JSONDecoder().decode(ExportPayload.self, from: plaintext),
              ISO8601DateFormatter().date(from: payload.exportedAt) != nil
                || fractionalDate(payload.exportedAt) != nil,
              (try? payload.vault.validated()) != nil else { throw ExportError.damaged }
        return payload
    }

    private static func fractionalDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
