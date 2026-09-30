import CryptoKit
import Foundation

// Only deterministic synthetic data. Never accepts a user's recovery key.
let raw = Data((0..<32).map { UInt8($0) })
let key = SymmetricKey(data: raw)
let aad = Data("PassBy.local-notebook.v1".utf8)
if CommandLine.arguments.last == "open" {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let sealed = try AES.GCM.SealedBox(combined: input)
    let plain = try AES.GCM.open(sealed, using: key, authenticating: aad)
    FileHandle.standardOutput.write(plain)
} else {
    let json = #"{"schemaVersion":1,"folders":[],"entries":[{"id":"11111111-1111-4111-8111-111111111111","title":"Example","account":"example@test.invalid","password":"Test-Only-Password","notes":"兼容性"}]}"#
    let sealed = try AES.GCM.seal(Data(json.utf8), using: key, authenticating: aad)
    let checksum = Data(SHA256.hash(data: raw)).prefix(2)
    let recovery = (raw + checksum).map { String(format: "%02X", $0) }.joined()
    let output = ["recovery": recovery, "ciphertext": sealed.combined!.base64EncodedString()]
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output))
}
