import SwiftUI

@main
struct AppDashboardApp: App {
    @StateObject private var store = StatusStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
                .task {
                    await store.refresh()
                }
        } label: {
            Image(systemName: "app.badge.checkmark")
        }
        .menuBarExtraStyle(.window)

        // Preferences window (⌘,): manage the app list and credentials.
        Settings {
            SettingsView(store: store)
        }
    }
}
