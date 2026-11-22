# App Dashboard

A macOS menu bar app that shows the release status of your apps across the
**App Store**, **Google Play** and **GitHub Releases** at a glance — version,
review state, rating and 30‑day downloads — with a one‑click link to each
app's release notes.

Built for indie developers who publish to App Store Connect and/or Google
Play and want a single place to see where every app stands. It talks directly
to the official APIs with your own credentials; nothing is sent anywhere else.

> The app's UI is in Swedish.

## Features

- **iOS** — current version, App Store review status, star rating and 30‑day
  downloads (via the App Store Connect API).
- **Android** — current version and track status (via the Google Play
  Developer API).
- **macOS** — latest version and download counts from public GitHub Releases.
- Auto‑refresh every 15 minutes, optional launch at login.
- Everything is configured in a **Settings window** — no code editing.

## Requirements

- macOS 14 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode, to build
- An **App Store Connect API key** for iOS version/review/rating data
- *(optional)* An App Store Connect API key with the **Sales** role plus your
  **vendor number**, for download numbers
- *(optional)* A **Google Play service‑account** JSON key, for Android data

Apps that only target one platform work fine — leave the other fields blank.

## Build

```bash
git clone https://github.com/mrjoakim/app-dashboard-mac.git
cd app-dashboard-mac
./build.sh
```

`build.sh` runs XcodeGen, builds with `xcodebuild`, installs **App Dashboard.app**
to `/Applications` and launches it. It lives in the menu bar (no Dock icon).

## Setup

1. Launch the app and open **Settings** (`⌘,`) from the gear icon in the menu.
2. **Appar** tab — add each app: name, App Store ID, store country, Android
   package name, GitHub `owner/repo`, and an optional release‑notes link.
3. **Nycklar** tab — select your credential files and fill in the issuer ID,
   key ID and vendor number.

Your app list is stored in macOS `UserDefaults`; credentials are written to
`~/.config/appdashboard/credentials.json`. Neither is ever part of the repo.
See [`apps.example.json`](apps.example.json) for the stored record shape.

### Getting the credentials

**App Store Connect API key** — App Store Connect → *Users and Access* →
*Integrations* → *App Store Connect API*. Generate a key (role *Admin* or
*Developer* for version/review data; generate a **second** key with the
*Sales* role for downloads). Download the `.p8` and note the **Issuer ID** and
**Key ID**.

**Vendor number** — App Store Connect → *Payments and Financial Reports*; it
is shown at the top left.

**Google Play service account** — in the Google Cloud Console create a service
account and download its JSON key, then grant it access in Play Console under
*Users and permissions*.

## License

[MIT](LICENSE) © Produktiv Friktion Media AB
