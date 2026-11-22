import Foundation

/// Public GitHub release download counters (no auth, no tracking).
enum GitHubReleases {
    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let download_count: Int
        }
        let tag_name: String
        let assets: [Asset]
    }

    struct Summary {
        let latestVersion: String
        let totalDownloads: Int
        let latestDownloads: Int
    }

    /// Sums .dmg downloads over all releases; the first release is the latest.
    static func summarize(_ releases: [Release]) -> Summary? {
        guard let latest = releases.first else { return nil }
        func dmgCount(_ r: Release) -> Int {
            r.assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
                .reduce(0) { $0 + $1.download_count }
        }
        let version = latest.tag_name.hasPrefix("v")
            ? String(latest.tag_name.dropFirst()) : latest.tag_name
        return Summary(
            latestVersion: version,
            totalDownloads: releases.reduce(0) { $0 + dmgCount($1) },
            latestDownloads: dmgCount(latest)
        )
    }

    static func text(_ s: Summary) -> String {
        "\(s.totalDownloads) nedladdningar totalt · \(s.latestDownloads) för \(s.latestVersion)"
    }

    /// Fetches the status for `repo` ("owner/name"). On failure the previous
    /// value is kept and only a short error is added.
    static func status(repo: String, previous: PlatformStatus?) async -> PlatformStatus {
        let pageURL = URL(string: "https://github.com/\(repo)/releases")
        do {
            var req = URLRequest(
                url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=100")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("AppDashboard", forHTTPHeaderField: "User-Agent")
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw URLError(.badServerResponse, userInfo: ["code": code]) }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            guard let summary = summarize(releases) else {
                return PlatformStatus(
                    configured: true, version: nil, status: .unknown, rating: nil,
                    ratingCount: nil, storeURL: pageURL, lastChecked: Date(), error: nil)
            }
            return PlatformStatus(
                configured: true, version: summary.latestVersion, status: .live, rating: nil,
                ratingCount: nil, installs: text(summary), storeURL: pageURL,
                lastChecked: Date(), error: nil)
        } catch {
            let code = ((error as? URLError)?.userInfo["code"] as? Int).map { "HTTP \($0)" }
            var kept = previous ?? PlatformStatus.loading
            kept.storeURL = pageURL
            kept.error = code ?? "GitHub ej nåbar"
            return kept
        }
    }
}
