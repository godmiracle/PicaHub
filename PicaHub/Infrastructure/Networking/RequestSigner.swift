import CryptoKit
import Foundation

struct RequestSigner: Sendable {
    let environment: APIEnvironment

    func signature(requestTarget: String, timestamp: String, method: HTTPMethod) -> String {
        let message = (
            requestTarget
                + timestamp
                + environment.nonce
                + method.rawValue
                + environment.apiKey
        ).lowercased()
        let key = SymmetricKey(data: Data(environment.secretKey.utf8))
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: key
        )
        return authenticationCode.map { String(format: "%02x", $0) }.joined()
    }
}
