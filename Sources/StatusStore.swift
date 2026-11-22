import SwiftUI
import Combine

@MainActor
final class StatusStore: ObservableObject {
    @Published var apps: [AppStatus] = []
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?
    @Published var credentialsMissing = false

    /// The user-editable app list. Owned here so the menu and the Settings
    /// window share one instance.
    let settings = AppSettings()

    private var ascClient: AppStoreConnectClient?
    private var playClient: GooglePlayClient?
    private var salesClient: AppStoreSalesClient?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        reloadCredentials()
        // Seed cards immediately so the UI has content before the first fetch.
        apps = settings.apps.map { placeholder(for: $0) }

        // React to edits from the Settings window: reconcile the cards (keeping
        // already-fetched data) and refetch, debounced so typing doesn't spam.
        settings.$apps
            .dropFirst()
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] newApps in
                guard let self else { return }
                self.reconcile(with: newApps)
                Task { await self.refresh() }
            }
            .store(in: &cancellables)

        startAutoRefresh()
    }

    /// (Re)load Apple/Google credentials from disk and rebuild the API clients.
    /// Call after the Settings window writes credentials.json.
    func reloadCredentials() {
        if let creds = Credentials.load() {
            ascClient = AppStoreConnectClient(credentials: creds)
            playClient = GooglePlayClient(serviceAccountPath: creds.googleServiceAccountPath)
            salesClient = AppStoreSalesClient(credentials: creds)
            credentialsMissing = false
        } else {
            ascClient = nil
            playClient = nil
            salesClient = nil
            credentialsMissing = true
        }
    }

    /// Refresh in the background on a fixed interval. The menu bar process stays
    /// alive even when the menu is closed, so this fires regardless of whether
    /// the dropdown is open.
    private func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Config.refreshInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    /// Rebuild the card list after an edit, preserving fetched data for apps
    /// that still exist so the UI doesn't flash back to placeholders.
    private func reconcile(with configs: [AppConfig]) {
        apps = configs.map { cfg in
            if var existing = apps.first(where: { $0.id == cfg.id }) {
                existing.name = cfg.name
                existing.releaseNotesURL = cfg.releaseNotesURL
                return existing
            }
            return placeholder(for: cfg)
        }
    }

    private func placeholder(for app: AppConfig) -> AppStatus {
        AppStatus(
            id: app.id,
            name: app.name,
            ios: app.iosAppStoreId == nil ? .notConfigured : .loading,
            android: (app.androidPackage != nil && playClient != nil) ? .loading : .notConfigured,
            mac: app.githubRepo == nil ? .notConfigured : .loading,
            releaseNotesURL: app.releaseNotesURL
        )
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Downloads for all iOS apps come from one per-vendor report set.
        let downloads = await salesClient?.downloads() ?? [:]

        var results: [AppStatus] = []
        for app in settings.apps {
            var ios = PlatformStatus.notConfigured
            if let appStoreId = app.iosAppStoreId, let client = ascClient {
                ios = await client.iosStatus(
                    appStoreId: appStoreId,
                    country: app.iosStoreCountry
                )
                if let units = downloads[appStoreId] {
                    ios.installs = "\(units)"
                }
            }
            var android = PlatformStatus.notConfigured
            if let pkg = app.androidPackage, let client = playClient {
                android = await client.androidStatus(packageName: pkg)
            }
            var mac = PlatformStatus.notConfigured
            if let repo = app.githubRepo {
                let previous = apps.first(where: { $0.id == app.id })?.mac
                mac = await GitHubReleases.status(repo: repo, previous: previous)
            }
            results.append(
                AppStatus(
                    id: app.id,
                    name: app.name,
                    ios: ios,
                    android: android,
                    mac: mac,
                    releaseNotesURL: app.releaseNotesURL
                )
            )
        }
        apps = results
        lastUpdated = Date()
    }
}
