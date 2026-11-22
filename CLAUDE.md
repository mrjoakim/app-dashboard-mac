# App Dashboard — macOS menyradsapp

Native SwiftUI `MenuBarExtra`-app som visar release-status för flera appar
(App Store, Google Play, GitHub Releases) i menyraden. Enda appen under
`~/Developer` som är **publik och open source (MIT)** — ett medvetet undantag
från privat-som-default i `~/Developer/CLAUDE.md`.

## Repo
Ett enda repo (`mrjoakim/app-dashboard-mac`), till skillnad från plattforms-
uppdelningen i andra workspaces. Standardbranch `main`.
- `Sources/` — all Swift-kod.
- `project.yml` — XcodeGen-källa; `*.xcodeproj` gitignoreras.
- `build.sh` — xcodegen → xcodebuild → installerar till `/Applications` → startar.
- `apps.example.json` — dokumenterar lagringsformatet för app-listan.

## Data utanför repot (aldrig i git)
- **App-listan** ägs av `AppSettings` och sparas i macOS UserDefaults. Källkoden
  (`Config.defaultApps`) är tom i publika bygget; varje användare lägger till
  sina appar via Settings-fönstret (⌘,).
- **Credentials** i `~/.config/appdashboard/credentials.json` (ASC-nyckel,
  ev. Sales-nyckel + vendor-nummer, ev. Google service-account). Skrivs av
  Settings-fönstret. `.p8`/`.json`-nycklar ligger utanför repot.

## Konventioner
- iOS/macOS 14+, SwiftUI, XcodeGen. Version i `project.yml`
  (`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`).
- Signering: ad-hoc lokalt; Developer ID + notarisering för distribuerade
  byggen (se release-flödet).
- Distribution: notariserad `.dmg` via GitHub Releases, länkad från sajten.

## Dokumentation
Backlog och noter ligger i Notion (privat, App Dashboard-vyn i App Backlog).
Inga privata länkar checkas in här eftersom repot är publikt.
