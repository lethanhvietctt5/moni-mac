// Checks an update archive's EdDSA signature against a public key, the way Sparkle checks it inside the
// installed app (Ed25519 over the whole archive). The release runs it with the key the built app ships, so a
// CI secret that doesn't match the committed public key fails the release instead of every user's update.
//
// Usage: swift scripts/release/verify-signature.swift <base64 public key> <archive> <base64 signature>
import CryptoKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: verify-signature.swift <public key> <archive> <signature>\n".utf8))
    exit(2)
}
let (keyText, path, signatureText) = (arguments[arguments.startIndex], arguments[arguments.startIndex + 1], arguments[arguments.startIndex + 2])
guard let keyData = Data(base64Encoded: keyText), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write(Data("error: '\(keyText)' isn't a base64 Ed25519 public key\n".utf8))
    exit(1)
}
guard let signature = Data(base64Encoded: signatureText), let archive = FileManager.default.contents(atPath: path) else {
    FileHandle.standardError.write(Data("error: unreadable signature or archive\n".utf8))
    exit(1)
}
guard key.isValidSignature(signature, for: archive) else {
    FileHandle.standardError.write(Data("error: the signature doesn't match the public key. Is SPARKLE_ED_PRIVATE_KEY the pair of SUPublicEDKey?\n".utf8))
    exit(1)
}
print("Signature verifies with \(keyText)")
