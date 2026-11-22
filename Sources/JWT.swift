import Foundation
import CryptoKit

enum JWTError: Error {
    case encoding
}

/// Base64URL without padding, per RFC 7515.
private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// Build a signed ES256 JWT for the App Store Connect API.
/// The .p8 is a PKCS#8 PEM EC key; CryptoKit's P256 signs it natively.
func makeAppStoreConnectJWT(
    issuerId: String,
    keyId: String,
    privateKeyPEM: String
) throws -> String {
    let now = Int(Date().timeIntervalSince1970)

    let header: [String: Any] = ["alg": "ES256", "kid": keyId, "typ": "JWT"]
    let payload: [String: Any] = [
        "iss": issuerId,
        "iat": now,
        "exp": now + 60 * 15, // ASC max lifetime is 20 min
        "aud": "appstoreconnect-v1",
    ]

    let headerData = try JSONSerialization.data(withJSONObject: header)
    let payloadData = try JSONSerialization.data(withJSONObject: payload)
    let signingInput = base64URL(headerData) + "." + base64URL(payloadData)

    guard let inputData = signingInput.data(using: .utf8) else {
        throw JWTError.encoding
    }

    let key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
    let signature = try key.signature(for: inputData)
    // ECDSASignature.rawRepresentation is r||s (64 bytes), exactly what ES256 wants.
    return signingInput + "." + base64URL(signature.rawRepresentation)
}
