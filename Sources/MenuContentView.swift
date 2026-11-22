import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: StatusStore
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if store.credentialsMissing {
                credentialsWarning
            }

            if store.apps.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(store.apps) { app in
                        AppCardView(app: app)
                    }
                }
                .padding(12)
            }

            Divider()

            loginToggle
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            footer
        }
        .frame(width: 340)
    }

    private var loginToggle: some View {
        Toggle("Starta vid inloggning", isOn: $launchAtLogin)
            .toggleStyle(.checkbox)
            .font(.caption)
            .onChange(of: launchAtLogin) { _, newValue in
                launchAtLogin = LoginItem.setEnabled(newValue)
            }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("App Dashboard")
                .font(.headline)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Inga appar än")
                .font(.subheadline.weight(.semibold))
            Text("Öppna Inställningar för att lägga till din första app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SettingsLink {
                Text("Öppna Inställningar")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
    }

    private var credentialsWarning: some View {
        HStack(spacing: 6) {
            Text("Apple-nycklar saknas – lägg till dem under Inställningar ▸ Nycklar.")
                .font(.caption)
                .foregroundStyle(.orange)
            SettingsLink {
                Text("Öppna")
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            if let updated = store.lastUpdated {
                Text("Uppdaterad \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Avsluta") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(12)
    }
}

struct AppCardView: View {
    let app: AppStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(app.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let url = app.releaseNotesURL {
                    Link(destination: url) {
                        Text("Release notes")
                            .font(.caption)
                    }
                }
            }

            PlatformRow(label: "iOS", status: app.ios)
            PlatformRow(label: "Android", status: app.android)
            if app.mac.configured {
                if let url = app.mac.storeURL {
                    Link(destination: url) {
                        PlatformRow(label: "Mac (GitHub)", status: app.mac)
                    }
                    .buttonStyle(.plain)
                } else {
                    PlatformRow(label: "Mac (GitHub)", status: app.mac)
                }
            }

            if let installs = app.ios.installs {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption2)
                    Text("\(installs) nedladdningar · 30 dgr (iOS)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }

            if let macInstalls = app.mac.installs {
                macDownloads(macInstalls)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

extension AppCardView {
    func macDownloads(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.circle")
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

struct PlatformRow: View {
    let label: String
    let status: PlatformStatus

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Text(status.version ?? "—")
                .font(.caption.weight(.medium))
                .frame(width: 44, alignment: .leading)

            Circle()
                .fill(status.status.color)
                .frame(width: 7, height: 7)
            Text(status.status.label)
                .font(.caption)

            Spacer()

            if let rating = status.rating {
                Text("★ \(rating, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let count = status.ratingCount {
                    Text("(\(count))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
