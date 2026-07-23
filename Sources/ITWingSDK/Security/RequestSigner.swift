import CryptoKit
import Foundation

struct RequestSigner {
    let apiKey: String

    func sign(method: String, path: String, timestamp: String, nonce: String, bodyHash: String) -> String {
        let payload = [method.uppercased(), path, timestamp, nonce, bodyHash].joined(separator: "\n")
        let key = SymmetricKey(data: Data(apiKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(signature).map { String(format: "%02x", $0) }.joined()
    }

    func sha256(_ value: Data) -> String {
        let digest = SHA256.hash(data: value)
        return Data(digest).map { String(format: "%02x", $0) }.joined()
    }
}

