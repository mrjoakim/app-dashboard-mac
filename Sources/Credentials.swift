import Foundation

/// Apple credentials loaded from ~/.config/appdashboard/credentials.json:
/// {
///   "appleIssuerId": "…",
///   "appleKeyId": "…",
///   "applePrivateKeyPath": "/Users/…/AuthKey_XXXX.p8"
/// }
struct Credentials: Decodable {
    let appleIssuerId: String
    let appleKeyId: String
    let applePrivateKeyPath: String
    /// Optional path to the Google Play service-account JSON key.
    let googleServiceAccountPath: String?
    /// Optional separate API key with the "Sales" role, used only for Sales
    /// reports (downloads). The version/review key lacks that access.
    let appleSalesKeyId: String?
    let appleSalesPrivateKeyPath: String?
    /// App Store Connect vendor number (required for Sales reports).
    let appleVendorNumber: String?

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/appdashboard/credentials.json")
    }

    static func load() -> Credentials? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    /// The PEM contents of the .p8 private key, read from disk.
    func privateKeyPEM() throws -> String {
        try String(contentsOfFile: applePrivateKeyPath, encoding: .utf8)
    }

    /// The PEM contents of the Sales-role .p8 key, read from disk.
    func salesPrivateKeyPEM() throws -> String {
        try String(contentsOfFile: appleSalesPrivateKeyPath ?? "", encoding: .utf8)
    }
}
