import Foundation

// MARK: - Auth

/// Response from POST /api/v2/pins
struct PlexPin: Decodable {
    let id: Int
    let code: String
    let authToken: String?
}

/// Persisted Plex credential (account token + identity).
struct PlexCredential: Codable {
    var authToken: String
    var username: String
    var clientID: String
}

/// GET /api/v2/user
struct PlexAccount: Decodable {
    let username: String?
    let title: String?
    let email: String?
    var displayName: String { username ?? title ?? email ?? "Plex" }
}

// MARK: - Resources (servers)

struct PlexResource: Decodable {
    let name: String
    let clientIdentifier: String
    let provides: String
    let accessToken: String?
    let connections: [PlexConnection]?

    var isServer: Bool { provides.contains("server") }
}

struct PlexConnection: Decodable {
    let `protocol`: String?
    let address: String?
    let port: Int?
    let uri: String
    let local: Bool?
    let relay: Bool?
}

/// A server we can query, with its candidate connection URIs (preference-ordered).
struct PlexServer: Identifiable, Hashable {
    let name: String
    let machineIdentifier: String
    let accessToken: String
    let connectionURIs: [URL]
    var id: String { machineIdentifier }
}

// MARK: - Library lookup

struct PlexMediaContainerResponse: Decodable {
    let mediaContainer: PlexMediaContainer
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

struct PlexMediaContainer: Decodable {
    let metadata: [PlexMetadata]?
    enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
}

struct PlexMetadata: Decodable {
    let ratingKey: String?
    let title: String?
    let type: String?
    let year: Int?
    let guid: String?
    let media: [PlexMedia]?
    let guids: [PlexGuid]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, title, type, year, guid
        case media = "Media"
        case guids = "Guid"
    }

    /// Best available video resolution label, e.g. "1080p" / "4K".
    var resolutionLabel: String? {
        guard let res = media?.compactMap(\.videoResolution).first else { return nil }
        switch res.lowercased() {
        case "4k": return "4K"
        case "sd": return "SD"
        default: return res + "p"
        }
    }

    func matchesTMDB(_ id: Int) -> Bool {
        let needle = "tmdb://\(id)"
        if let guid, guid.contains(needle) { return true }
        if let guids, guids.contains(where: { $0.id?.contains(needle) == true }) { return true }
        return false
    }
}

struct PlexGuid: Decodable {
    let id: String?
}

struct PlexMedia: Decodable {
    let videoResolution: String?
}

/// A concrete playable match surfaced on the detail page.
struct PlexMatch: Hashable {
    let serverName: String
    let resolution: String?
    let deepLink: URL
}
