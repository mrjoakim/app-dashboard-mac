import Foundation

/// Manages "launch at login" via a LaunchAgent plist in ~/Library/LaunchAgents.
///
/// Chosen over SMAppService because this app is ad-hoc signed: its code
/// signature changes on every rebuild, which would invalidate an SMAppService
/// login item. A LaunchAgent keys off the app's path instead, so it survives
/// rebuilds.
enum LoginItem {
    static let label = "com.mrjoakim.appdashboard"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if enabled { enable() } else { disable() }
        return isEnabled
    }

    private static func enable() {
        let appPath = Bundle.main.bundlePath
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>\(appPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
        try? FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
        launchctl(["bootout", "gui/\(getuid())", plistURL.path]) // clear any stale copy
        launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private static func disable() {
        launchctl(["bootout", "gui/\(getuid())", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func launchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}
