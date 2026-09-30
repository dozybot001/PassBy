import CryptoKit
import XCTest
@testable import PassBy

final class PasswordGeneratorTests: XCTestCase {
    func testEveryEnabledTypeIsPresentAtEverySupportedLength() throws {
        for length in 8...24 {
            var options = PasswordOptions()
            options.length = length
            let generated = try PasswordGenerator.generate(options: options)
            XCTAssertEqual(generated.count, length)
            for alphabet in options.alphabets { XCTAssertTrue(generated.contains { alphabet.contains($0) }) }
        }
    }

    func testOnlySelectedTypesAreGenerated() throws {
        var options = PasswordOptions()
        options.lowercase = false; options.uppercase = false; options.symbols = false
        XCTAssertTrue(try PasswordGenerator.generate(options: options).allSatisfy { "0123456789".contains($0) })
        options.digits = false
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options))
        options.lowercase = true; options.length = 7
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options))
        options.length = 25
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options))
    }

    func testDraftIsOnlyInEncryptedLocalSnapshot() throws {
        let draft = VaultEntry(password: "draft-secret-unique", notes: "unfinished")
        let state = LocalVaultState(current: Vault(), base: Vault(), draft: draft)
        let key = SymmetricKey(size: .bits256)
        let data = try VaultCipher.sealLocal(state, key: key)
        XCTAssertNil(data.range(of: Data(draft.password.utf8)))
        XCTAssertEqual(try VaultCipher.openLocal(data, key: key).draft, draft)
        XCTAssertTrue(state.current.entries.isEmpty)
    }
}
