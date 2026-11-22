import Foundation

enum ASCError: Error, CustomStringConvertible {
    case http(Int, String)
    case decode

    var description: String {
        switch self {
        case let .http(code, body): return "ASC \(code): \(body.prefix(200))"
        case .decode: return "decode error"
        }
    }
}

/// Maps App Store version states to our simplified ReleaseStatus.
/// https://developer.apple.com/documentation/appstoreconnectapi/appstoreversionstate
private func mapVersionState(_ state: String) -> ReleaseStatus {
    switch state {
    case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION":
        return .live
    case "WAITING_FOR_REVIEW", "IN_REVIEW":
        return .inReview
    case "PREPARE_FOR_SUBMISSION", "DEVELOPER_REMOVED_FROM_SALE", "REPLACED_WITH_NEW_VERSION":
        return .draft
    case "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "PROCESSING_FOR_APP_STORE":
        return .pendingRelease
    case "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY":
        return .rejected
    default:
        return .unknown
    }
}

actor AppStoreConnectClient {
    private let creds: Credentials
    private var cachedToken: (token: String, exp: Date)?

    init(credentials: Credentials) {
        self.creds = credentials
    }

    private func token() throws -> String {
        if let cached = cachedToken, cached.exp.timeIntervalSinceNow > 60 {
            return cached.token
        }
        let pem = try creds.privateKeyPEM()
        let jwt = try makeAppStoreConnectJWT(
            issuerId: creds.appleIssuerId,
            keyId: creds.appleKeyId,
            privateKeyPEM: pem
        )
        cachedToken = (jwt, Date().addingTimeInterval(60 * 14))
        return jwt
    }

    private func get(_ path: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1\(path)")!)
        req.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw ASCError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Response shapes

    private struct VersionsResponse: Decodable {
        struct Item: Decodable { let attributes: Attributes }
        struct Attributes: Decodable {
            let versionString: String
            let appStoreState: String
        }
        let data: [Item]
    }

    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let averageUserRating: Double?
            let userRatingCount: Int?
        }
        let results: [Result]
    }

    // MARK: - Public

    func iosStatus(appStoreId: String, country: String) async -> PlatformStatus {
        let storeURL = URL(string: "https://apps.apple.com/\(country)/app/id\(appStoreId)")
        var status = PlatformStatus(
            configured: true,
            version: nil,
            status: .unknown,
            rating: nil,
            ratingCount: nil,
            storeURL: storeURL,
            lastChecked: Date(),
            error: nil
        )

        async let ratingsTask = ratings(appStoreId: appStoreId, country: country)

        do {
            let data = try await get(
                "/apps/\(appStoreId)/appStoreVersions?limit=5&fields[appStoreVersions]=versionString,appStoreState"
            )
            let decoded = try JSONDecoder().decode(VersionsResponse.self, from: data)
            if let newest = decoded.data.first {
                status.version = newest.attributes.versionString
                status.status = mapVersionState(newest.attributes.appStoreState)
            }
        } catch {
            status.status = .unknown
            status.error = String(describing: error)
        }

        let r = await ratingsTask
        status.rating = r.rating
        status.ratingCount = r.count
        return status
    }

    /// Public average rating + count from the iTunes lookup API (no auth).
    private func ratings(appStoreId: String, country: String) async
        -> (rating: Double?, count: Int?)
    {
        let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreId)&country=\(country)")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
            let r = decoded.results.first
            return (r?.averageUserRating, r?.userRatingCount)
        } catch {
            return (nil, nil)
        }
    }
}
