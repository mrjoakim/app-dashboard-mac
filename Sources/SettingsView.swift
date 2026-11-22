import SwiftUI
import UniformTypeIdentifiers

/// Preferences window: an "Appar" tab to manage the dashboard's app list and a
/// "Nycklar" tab for the Apple/Google credentials.
struct SettingsView: View {
    @ObservedObject var store: StatusStore

    var body: some View {
        TabView {
            AppsSettingsView(settings: store.settings)
                .tabItem { Label("Appar", systemImage: "square.grid.2x2") }

            CredentialsSettingsView(store: store)
                .tabItem { Label("Nycklar", systemImage: "key") }
        }
        .frame(width: 540, height: 460)
    }
}

// MARK: - Apps

struct AppsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var selection: AppConfig.ID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(settings.apps) { app in
                    Text(app.name.isEmpty ? "(namnlös)" : app.name)
                        .tag(app.id)
                }
                .onMove(perform: settings.move)
                .onDelete(perform: settings.delete)
            }
            .frame(minHeight: 150)

            HStack(spacing: 6) {
                Button {
                    let new = settings.add()
                    selection = new.id
                } label: { Image(systemName: "plus") }

                Button {
                    if let id = selection,
                       let app = settings.apps.first(where: { $0.id == id }) {
                        settings.delete(app)
                        selection = nil
                    }
                } label: { Image(systemName: "minus") }
                .disabled(selection == nil)

                Spacer()
                Text("\(settings.apps.count) appar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            Group {
                if let id = selection,
                   let app = settings.apps.first(where: { $0.id == id }),
                   let binding = settings.binding(for: app) {
                    AppEditor(app: binding)
                } else {
                    VStack {
                        Spacer()
                        Text(settings.apps.isEmpty
                             ? "Lägg till din första app med +"
                             : "Välj en app för att redigera")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct AppEditor: View {
    @Binding var app: AppConfig

    var body: some View {
        Form {
            TextField("Namn", text: $app.name)

            Section("App Store (iOS)") {
                TextField("App Store-ID", text: optional($app.iosAppStoreId),
                          prompt: Text("t.ex. 6761601848"))
                TextField("Land", text: $app.iosStoreCountry,
                          prompt: Text("se"))
            }

            Section("Google Play (Android)") {
                TextField("Paketnamn", text: optional($app.androidPackage),
                          prompt: Text("com.exempel.app"))
            }

            Section("macOS (GitHub Releases)") {
                TextField("Repo", text: optional($app.githubRepo),
                          prompt: Text("owner/name"))
            }

            Section("Release notes") {
                TextField("Länk", text: optional($app.notionURL),
                          prompt: Text("https://…"))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Credentials

struct CredentialsSettingsView: View {
    @ObservedObject var store: StatusStore

    @State private var issuerId = ""
    @State private var keyId = ""
    @State private var privateKeyPath = ""
    @State private var googleServiceAccountPath = ""
    @State private var salesKeyId = ""
    @State private var salesKeyPath = ""
    @State private var vendorNumber = ""
    @State private var saved = false

    private var coreConfigured: Bool {
        !issuerId.isEmpty && !keyId.isEmpty && !privateKeyPath.isEmpty
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: coreConfigured
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(coreConfigured ? .green : .orange)
                    Text(coreConfigured
                         ? "App Store Connect-nyckel konfigurerad"
                         : "Grundnyckel saknas – fyll i issuer, key-id och .p8")
                        .font(.callout)
                }
            }

            Section("App Store Connect") {
                TextField("Issuer-ID", text: $issuerId)
                TextField("Key-ID", text: $keyId)
                filePicker("Privat nyckel (.p8)", path: $privateKeyPath, types: [.item])
            }

            Section("Nedladdningar (Sales-nyckel, valfri)") {
                TextField("Sales key-ID", text: $salesKeyId)
                filePicker("Sales-nyckel (.p8)", path: $salesKeyPath, types: [.item])
                TextField("Vendor-nummer", text: $vendorNumber)
            }

            Section("Google Play (valfri)") {
                filePicker("Service-account (.json)", path: $googleServiceAccountPath, types: [.json])
            }

            Section {
                HStack {
                    Button("Spara") { save() }
                        .keyboardShortcut(.defaultAction)
                    if saved {
                        Label("Sparat", systemImage: "checkmark")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    Spacer()
                    Text(Credentials.configURL.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func filePicker(_ label: String, path: Binding<String>, types: [UTType]) -> some View {
        FilePickerRow(label: label, path: path, types: types)
    }

    private func load() {
        guard let creds = Credentials.load() else { return }
        issuerId = creds.appleIssuerId
        keyId = creds.appleKeyId
        privateKeyPath = creds.applePrivateKeyPath
        googleServiceAccountPath = creds.googleServiceAccountPath ?? ""
        salesKeyId = creds.appleSalesKeyId ?? ""
        salesKeyPath = creds.appleSalesPrivateKeyPath ?? ""
        vendorNumber = creds.appleVendorNumber ?? ""
    }

    private func save() {
        var dict: [String: String] = [
            "appleIssuerId": issuerId,
            "appleKeyId": keyId,
            "applePrivateKeyPath": privateKeyPath,
        ]
        func put(_ key: String, _ value: String) {
            if !value.trimmingCharacters(in: .whitespaces).isEmpty { dict[key] = value }
        }
        put("googleServiceAccountPath", googleServiceAccountPath)
        put("appleSalesKeyId", salesKeyId)
        put("appleSalesPrivateKeyPath", salesKeyPath)
        put("appleVendorNumber", vendorNumber)

        let url = Credentials.configURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }

        store.reloadCredentials()
        Task { await store.refresh() }

        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}

/// One credential-file row with its own importer, so several can coexist.
private struct FilePickerRow: View {
    let label: String
    @Binding var path: String
    let types: [UTType]
    @State private var picking = false

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(path.isEmpty ? "Ingen vald" : (path as NSString).lastPathComponent)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Välj…") { picking = true }
                if !path.isEmpty {
                    Button { path = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: types) { result in
            if case .success(let url) = result { path = url.path }
        }
    }
}

/// Bridges a `String?` model field to the non-optional binding a TextField needs,
/// storing nil when the field is cleared.
private func optional(_ source: Binding<String?>) -> Binding<String> {
    Binding(
        get: { source.wrappedValue ?? "" },
        set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
    )
}
