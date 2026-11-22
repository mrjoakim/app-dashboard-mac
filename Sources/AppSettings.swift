import SwiftUI

/// The live, user-editable list of apps shown on the dashboard. Persisted as
/// JSON in UserDefaults so it survives rebuilds and is independent of the
/// source code — that's what lets the app ship with an empty `Config.defaultApps`
/// and still remember each user's own apps.
@MainActor
final class AppSettings: ObservableObject {
    @Published var apps: [AppConfig] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private static let storageKey = "apps.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([AppConfig].self, from: data) {
            apps = decoded
        } else {
            // First run: seed from the compiled-in defaults and persist, so the
            // list is owned by storage from here on.
            apps = Config.defaultApps
            save()
        }
    }

    // MARK: - Mutations

    func add() -> AppConfig {
        let new = AppConfig(name: "Ny app")
        apps.append(new)
        return new
    }

    func delete(_ app: AppConfig) {
        apps.removeAll { $0.id == app.id }
    }

    func delete(at offsets: IndexSet) {
        apps.remove(atOffsets: offsets)
    }

    func move(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
    }

    /// Binding into a specific app by id, so editing a row writes straight back
    /// into the stored array.
    func binding(for app: AppConfig) -> Binding<AppConfig>? {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return nil }
        return Binding(
            get: { self.apps[index] },
            set: { self.apps[index] = $0 }
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
