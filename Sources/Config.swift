import Foundation

struct AppConfig: Codable, Identifiable, Equatable {
    /// Stable identity. Seed apps use a readable slug; apps added through the
    /// Settings UI get a generated UUID.
    let id: String
    var name: String
    /// Notion page the "Release notes" link opens. Points directly at the app's
    /// release-notes page/database (Spårhunden has a dedicated database; the
    /// rest use a "<App> iOS – Release notes" löpande logg in SB_Notes). Docs
    /// moved from Obsidian to Notion 2026-10-20. nil/empty = no link shown.
    var notionURL: String?
    var iosAppStoreId: String?
    var iosStoreCountry: String
    var androidPackage: String?
    /// "owner/name" of a GitHub repo whose release downloads are shown (macOS apps).
    var githubRepo: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        notionURL: String? = nil,
        iosAppStoreId: String? = nil,
        iosStoreCountry: String = "se",
        androidPackage: String? = nil,
        githubRepo: String? = nil
    ) {
        self.id = id
        self.name = name
        self.notionURL = notionURL
        self.iosAppStoreId = iosAppStoreId
        self.iosStoreCountry = iosStoreCountry
        self.androidPackage = androidPackage
        self.githubRepo = githubRepo
    }

    /// The release-notes link, or nil when unset/blank.
    var releaseNotesURL: URL? {
        guard let s = notionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return URL(string: s)
    }

    // Tolerate older stored records that predate a field, and apps added via
    // the UI that omit optionals.
    enum CodingKeys: String, CodingKey {
        case id, name, notionURL, iosAppStoreId, iosStoreCountry, androidPackage, githubRepo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        notionURL = try c.decodeIfPresent(String.self, forKey: .notionURL)
        iosAppStoreId = try c.decodeIfPresent(String.self, forKey: .iosAppStoreId)
        iosStoreCountry = try c.decodeIfPresent(String.self, forKey: .iosStoreCountry) ?? "se"
        androidPackage = try c.decodeIfPresent(String.self, forKey: .androidPackage)
        githubRepo = try c.decodeIfPresent(String.self, forKey: .githubRepo)
    }
}

enum Config {
    /// How often to auto-refresh, in seconds.
    static let refreshInterval: TimeInterval = 15 * 60

    /// First-run seed only. The live app list is owned by ``AppSettings`` and
    /// persisted in UserDefaults; this is copied in once when no stored list
    /// exists yet. Public builds ship this empty — use the Settings window
    /// (⌘,) to add your own apps.
    /// Empty in public builds: the app ships with no apps baked in, and each
    /// user adds their own through the Settings window (⌘,). See
    /// `apps.example.json` in the repo root for the stored record shape.
    static let defaultApps: [AppConfig] = []
}
