import SwiftUI

enum ReleaseStatus: String {
    case notConfigured
    case live
    case inReview
    case pendingRelease
    case rejected
    case draft
    case unknown

    var label: String {
        switch self {
        case .notConfigured: return "Ej konfigurerad"
        case .live: return "Live"
        case .inReview: return "I review"
        case .pendingRelease: return "Väntar på utrullning"
        case .rejected: return "Avvisad"
        case .draft: return "Utkast"
        case .unknown: return "Okänd"
        }
    }

    var color: Color {
        switch self {
        case .live: return .green
        case .inReview: return .orange
        case .pendingRelease: return .blue
        case .rejected: return .red
        case .notConfigured, .draft, .unknown: return .gray
        }
    }
}

struct PlatformStatus {
    var configured: Bool
    var version: String?
    var status: ReleaseStatus
    var rating: Double?
    var ratingCount: Int?
    /// Downloads over the last 30 days, pre-formatted for display.
    var installs: String? = nil
    var storeURL: URL?
    var lastChecked: Date?
    var error: String?

    static let notConfigured = PlatformStatus(
        configured: false,
        version: nil,
        status: .notConfigured,
        rating: nil,
        ratingCount: nil,
        storeURL: nil,
        lastChecked: nil,
        error: nil
    )

    /// Configured but not yet fetched — shown before the first refresh returns.
    static let loading = PlatformStatus(
        configured: true,
        version: nil,
        status: .unknown,
        rating: nil,
        ratingCount: nil,
        storeURL: nil,
        lastChecked: nil,
        error: nil
    )
}

struct AppStatus: Identifiable {
    let id: String
    var name: String
    var ios: PlatformStatus
    var android: PlatformStatus
    var mac: PlatformStatus = .notConfigured
    var releaseNotesURL: URL?
}
