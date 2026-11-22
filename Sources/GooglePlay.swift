import Foundation
import Security

// MARK: - Service account key

struct GoogleServiceAccount: Decodable {
    let clientEmail: String
    let privateKey: String
    let tokenURI: String

    enum CodingKeys: String, CodingKey {
        case clientEmail = "client_email"
        case privateKey = "private_key"
        case tokenURI = "token_uri"
    }
}

enum GoogleError: Error, CustomStringConvertible {
    case keyParse(String)
    case http(Int, String)
    case noToken

    var description: String {
        switch self {
        case let .keyParse(m): return "key parse: \(m)"
        case let .http(c, b): return "GP \(c): \(b.prefix(160))"
        case .noToken: return "no access token"
        }
    }
}

// MARK: - RSA (RS256) signing via Security framework

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// Strip the PEM armor and base64-decode to DER.
private func pemToDER(_ pem: String) -> Data? {
    let body = pem
        .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
        .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
        .replacingOccurrences(of: "\\n", with: "")
        .components(separatedBy: .whitespacesAndNewlines)
        .joined()
    return Data(base64Encoded: body)
}

/// Read a DER length starting at `i`; returns (length, bytesConsumed).
private func derLength(_ b: [UInt8], _ i: Int) -> (Int, Int)? {
    guard i < b.count else { return nil }
    let first = b[i]
    if first < 0x80 { return (Int(first), 1) }
    let count = Int(first & 0x7f)
    guard count > 0, i + count < b.count else { return nil }
    var len = 0
    for j in 1...count { len = (len << 8) | Int(b[i + j]) }
    return (len, 1 + count)
}

/// Extract the PKCS#1 RSAPrivateKey from a PKCS#8 PrivateKeyInfo DER.
private func pkcs1(fromPKCS8 der: Data) -> Data? {
    let b = [UInt8](der)
    var i = 0
    guard i < b.count, b[i] == 0x30 else { return nil } // SEQUENCE
    i += 1
    guard let (_, seqLenBytes) = derLength(b, i) else { return nil }
    i += seqLenBytes
    guard i < b.count, b[i] == 0x02 else { return nil } // version INTEGER
    i += 1
    guard let (vLen, vLenBytes) = derLength(b, i) else { return nil }
    i += vLenBytes + vLen
    guard i < b.count, b[i] == 0x30 else { return nil } // AlgorithmIdentifier SEQUENCE
    i += 1
    guard let (aLen, aLenBytes) = derLength(b, i) else { return nil }
    i += aLenBytes + aLen
    guard i < b.count, b[i] == 0x04 else { return nil } // OCTET STRING
    i += 1
    guard let (oLen, oLenBytes) = derLength(b, i) else { return nil }
    i += oLenBytes
    guard i + oLen <= b.count else { return nil }
    return Data(b[i..<(i + oLen)])
}

private func rsaSignSHA256(_ message: Data, pemPKCS8: String) throws -> Data {
    guard let der = pemToDER(pemPKCS8) else { throw GoogleError.keyParse("pem decode") }
    guard let pkcs1Key = pkcs1(fromPKCS8: der) else { throw GoogleError.keyParse("pkcs8→pkcs1") }
    let attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(pkcs1Key as CFData, attrs as CFDictionary, &error) else {
        throw GoogleError.keyParse(String(describing: error?.takeRetainedValue()))
    }
    guard let sig = SecKeyCreateSignature(
        key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error
    ) else {
        throw GoogleError.keyParse(String(describing: error?.takeRetainedValue()))
    }
    return sig as Data
}

// MARK: - Client

/// Google's release `name` is often "<versionCode> (<versionName>)", e.g.
/// "19 (2.1)". Prefer the human versionName in the parentheses; fall back to
/// the raw name, then to the version codes.
private func cleanVersion(name: String?, versionCodes: [String]?) -> String? {
    if let name, let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"),
       open < close {
        let inner = String(name[name.index(after: open)..<close])
        if !inner.isEmpty { return inner }
    }
    return name ?? versionCodes?.joined(separator: ", ")
}

private func mapTrackStatus(_ status: String) -> ReleaseStatus {
    switch status {
    case "completed": return .live
    case "inProgress": return .pendingRelease
    case "draft": return .draft
    case "halted": return .unknown
    default: return .unknown
    }
}

actor GooglePlayClient {
    private let account: GoogleServiceAccount
    private var cachedToken: (token: String, exp: Date)?

    /// Returns nil if the key file is missing or unreadable.
    init?(serviceAccountPath: String?) {
        guard let path = serviceAccountPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let account = try? JSONDecoder().decode(GoogleServiceAccount.self, from: data)
        else { return nil }
        self.account = account
    }

    private func accessToken() async throws -> String {
        if let c = cachedToken, c.exp.timeIntervalSinceNow > 60 { return c.token }

        let now = Int(Date().timeIntervalSince1970)
        let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"])
        let claims = try JSONSerialization.data(withJSONObject: [
            "iss": account.clientEmail,
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": account.tokenURI,
            "iat": now,
            "exp": now + 3600,
        ])
        let signingInput = base64URL(header) + "." + base64URL(claims)
        let signature = try rsaSignSHA256(Data(signingInput.utf8), pemPKCS8: account.privateKey)
        let assertion = signingInput + "." + base64URL(signature)

        var req = URLRequest(url: URL(string: account.tokenURI)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(assertion)"
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GoogleError.http(code, String(data: data, encoding: .utf8) ?? "") }
        struct TokenResponse: Decodable { let access_token: String; let expires_in: Int }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = (token.access_token, Date().addingTimeInterval(TimeInterval(token.expires_in - 60)))
        return token.access_token
    }

    private func apiGET(_ url: String, token: String) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GoogleError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return data
    }

    // Response shapes
    private struct EditResponse: Decodable { let id: String }
    private struct TracksResponse: Decodable {
        struct Track: Decodable {
            let track: String
            let releases: [Release]?
        }
        struct Release: Decodable {
            let name: String?
            let status: String?
            let versionCodes: [String]?
        }
        let tracks: [Track]
    }

    func androidStatus(packageName: String) async -> PlatformStatus {
        let storeURL = URL(string:
            "https://play.google.com/store/apps/details?id=\(packageName)&gl=SE")
        var status = PlatformStatus(
            configured: true, version: nil, status: .unknown,
            rating: nil, ratingCount: nil, storeURL: storeURL,
            lastChecked: Date(), error: nil
        )

        do {
            let token = try await accessToken()
            let base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)"

            // An "edit" (a transient snapshot) is required to read track state.
            guard let editId = try await createEdit(base: base, token: token) else {
                status.error = "no edit"; return status
            }

            let tracksData = try await apiGET("\(base)/edits/\(editId)/tracks", token: token)
            let tracks = try JSONDecoder().decode(TracksResponse.self, from: tracksData).tracks

            // Prefer the most public track that has a release.
            let priority = ["production", "beta", "alpha", "internal"]
            let ordered = tracks.sorted {
                (priority.firstIndex(of: $0.track) ?? 99) < (priority.firstIndex(of: $1.track) ?? 99)
            }
            if let release = ordered.compactMap({ $0.releases?.first }).first {
                status.version = cleanVersion(
                    name: release.name, versionCodes: release.versionCodes)
                status.status = mapTrackStatus(release.status ?? "")
            }

            await deleteEdit(base: base, editId: editId, token: token)
        } catch {
            status.status = .unknown
            status.error = String(describing: error)
        }
        return status
    }

    private func createEdit(base: String, token: String) async throws -> String? {
        var req = URLRequest(url: URL(string: "\(base)/edits")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GoogleError.http(code, String(data: data, encoding: .utf8) ?? "") }
        return try JSONDecoder().decode(EditResponse.self, from: data).id
    }

    private func deleteEdit(base: String, editId: String, token: String) async {
        var req = URLRequest(url: URL(string: "\(base)/edits/\(editId)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }
}
