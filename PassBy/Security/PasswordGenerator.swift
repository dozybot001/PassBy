import Foundation
import Security

struct PasswordOptions: Equatable {
    var length = 20
    var lowercase = true
    var uppercase = true
    var digits = true
    var symbols = true

    var alphabets: [[Character]] {
        var values: [[Character]] = []
        if lowercase { values.append(Array("abcdefghijklmnopqrstuvwxyz")) }
        if uppercase { values.append(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
        if digits { values.append(Array("0123456789")) }
        if symbols { values.append(Array("!@#$%^&*()-_=+[]{}:,.?")) }
        return values
    }
}

enum PasswordGenerator {
    static func generate(options: PasswordOptions) throws -> String {
        let alphabets = options.alphabets
        guard (12...64).contains(options.length), !alphabets.isEmpty else {
            throw PasswordGenerationError.invalidOptions
        }
        let pool = alphabets.flatMap { $0 }
        // Guarantee each enabled type, then randomize its position.
        var result = try alphabets.map { try $0[randomIndex(upperBound: $0.count)] }
        while result.count < options.length {
            result.append(try pool[randomIndex(upperBound: pool.count)])
        }
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            result.swapAt(index, try randomIndex(upperBound: index + 1))
        }
        return String(result)
    }

    private static func randomIndex(upperBound: Int) throws -> Int {
        let bound = UInt32(upperBound)
        let limit = UInt32.max - UInt32.max % bound
        var sample: UInt32 = 0
        // Rejection sampling removes modulo bias. SecRandomCopyBytes uses the
        // OS cryptographically secure random source, never a timestamp or seed.
        repeat {
            guard SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &sample) == errSecSuccess else {
                throw PasswordGenerationError.randomUnavailable
            }
        } while sample >= limit
        return Int(sample % bound)
    }
}

enum PasswordGenerationError: Error, LocalizedError {
    case invalidOptions, randomUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidOptions: return L("Choose at least one character type.")
        case .randomUnavailable: return L("A secure password could not be generated. Please try again.")
        }
    }
}
