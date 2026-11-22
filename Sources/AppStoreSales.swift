import Foundation

/// Fetches App Store Connect Sales reports and sums downloads per app over the
/// last ~30 days. Uses a separate "Sales"-role API key (the version/review key
/// lacks report access). Daily reports are cached on disk since finalized
/// reports never change — only new days are fetched on later refreshes.
actor AppStoreSalesClient {
    private let issuerId: String
    private let keyId: String
    private let keyPEM: String
    private let vendor: String
    private let cacheDir: URL
    private var cachedToken: (token: String, exp: Date)?

    init?(credentials c: Credentials) {
        guard let kid = c.appleSalesKeyId,
              let vendor = c.appleVendorNumber,
              let pem = try? c.salesPrivateKeyPEM(), !pem.isEmpty
        else { return nil }
        self.issuerId = c.appleIssuerId
        self.keyId = kid
        self.keyPEM = pem
        self.vendor = vendor
        self.cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/appdashboard/cache/sales")
        try? FileManager.default.createDirectory(
            at: cacheDir, withIntermediateDirectories: true)
    }

    private func token() throws -> String {
        if let c = cachedToken, c.exp.timeIntervalSinceNow > 60 { return c.token }
        let jwt = try makeAppStoreConnectJWT(
            issuerId: issuerId, keyId: keyId, privateKeyPEM: keyPEM)
        cachedToken = (jwt, Date().addingTimeInterval(60 * 14))
        return jwt
    }

    /// Returns [Apple Identifier (App Store id as String): download units] summed
    /// over the last 30 available days.
    func downloads() async -> [String: Int] {
        guard let tk = try? token() else { return [:] }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "America/Los_Angeles")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let cal = Calendar(identifier: .gregorian)
        let dates: [String] = (1...30).compactMap { off in
            cal.date(byAdding: .day, value: -off, to: Date()).map(fmt.string)
        }

        let vendor = self.vendor
        let cacheDir = self.cacheDir
        var tsvs: [String] = []
        await withTaskGroup(of: String?.self) { group in
            for date in dates {
                let cacheURL = cacheDir.appendingPathComponent("SALES_\(date).tsv")
                group.addTask {
                    await Self.reportTSV(
                        date: date, token: tk, vendor: vendor, cacheURL: cacheURL)
                }
            }
            for await r in group { if let r { tsvs.append(r) } }
        }

        var totals: [String: Int] = [:]
        for tsv in tsvs { accumulate(tsv, into: &totals) }
        return totals
    }

    /// Sum download Units per Apple Identifier, excluding updates (product type
    /// starting "7") and in-app purchases (starting "IA").
    private func accumulate(_ tsv: String, into totals: inout [String: Int]) {
        for line in tsv.split(separator: "\n").dropFirst() {
            let f = String(line).components(separatedBy: "\t")
            guard f.count > 14 else { continue }
            let productType = f[6]
            if productType.hasPrefix("7") || productType.hasPrefix("IA") { continue }
            guard let units = Int(f[7].trimmingCharacters(in: .whitespaces)) else { continue }
            let appleId = f[14].trimmingCharacters(in: .whitespaces)
            totals[appleId, default: 0] += units
        }
    }

    private static func reportTSV(
        date: String, token: String, vendor: String, cacheURL: URL
    ) async -> String? {
        if let data = try? Data(contentsOf: cacheURL),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        var comps = URLComponents(
            string: "https://api.appstoreconnect.apple.com/v1/salesReports")!
        comps.queryItems = [
            .init(name: "filter[frequency]", value: "DAILY"),
            .init(name: "filter[reportType]", value: "SALES"),
            .init(name: "filter[reportSubType]", value: "SUMMARY"),
            .init(name: "filter[vendorNumber]", value: vendor),
            .init(name: "filter[reportDate]", value: date),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/a-gzip", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let tsvData = Gzip.inflate(data),
              let tsv = String(data: tsvData, encoding: .utf8)
        else { return nil } // not ready / no data for that day — skip, retry later
        try? tsv.write(to: cacheURL, atomically: true, encoding: .utf8)
        return tsv
    }
}
