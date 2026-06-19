import Foundation
import SwiftUI

/// Stateless Plex HTTP: discover servers, match a TMDB title in a library,
/// and build a "open in Plex" deep link.
struct PlexService {
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        return URLSession(configuration: cfg)
    }()

    // MARK: Servers

    func loadServers(token: String) async -> [PlexServer] {
        var comps = URLComponents(string: AppConfig.plexResourcesURL)!
        comps.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
        ]
        var req = URLRequest(url: comps.url!)
        PlexAuth.headers(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let resources = try? JSONDecoder().decode([PlexResource].self, from: data)
        else { return [] }

        return resources.filter(\.isServer).compactMap { res in
            let uris = orderedURIs(res.connections ?? [])
            guard !uris.isEmpty else { return nil }
            return PlexServer(
                name: res.name,
                machineIdentifier: res.clientIdentifier,
                accessToken: res.accessToken ?? token,
                connectionURIs: uris
            )
        }
    }

    private func orderedURIs(_ connections: [PlexConnection]) -> [URL] {
        func rank(_ c: PlexConnection) -> Int {
            if c.local == true { return 0 }          // LAN first
            if c.relay != true { return 1 }          // direct public
            return 2                                  // relay last
        }
        return connections
            .sorted { rank($0) < rank($1) }
            .compactMap { URL(string: $0.uri) }
    }

    // MARK: Matching

    func findMatch(server: PlexServer, ref: MediaRef, title: String, year: String?) async -> PlexMetadata? {
        let type = ref.type == .movie ? "1" : "2"

        for base in server.connectionURIs {
            // First reachable connection wins; query it by GUID, then by title.
            guard let byGuid = await query(base: base, token: server.accessToken, path: "/library/all",
                                           items: [URLQueryItem(name: "guid", value: "tmdb://\(ref.id)"),
                                                   URLQueryItem(name: "type", value: type)])
            else { continue }  // unreachable → try next connection

            if let hit = byGuid.first(where: { $0.matchesTMDB(ref.id) }) ?? byGuid.first {
                return hit
            }
            if let byTitle = await query(base: base, token: server.accessToken, path: "/library/all",
                                         items: [URLQueryItem(name: "title", value: title),
                                                 URLQueryItem(name: "type", value: type)]),
               let hit = matchByTitle(byTitle, title: title, year: year) {
                return hit
            }
            return nil  // server reachable, no match here
        }
        return nil
    }

    private func query(base: URL, token: String, path: String, items: [URLQueryItem]) async -> [PlexMetadata]? {
        var comps = URLComponents(url: base.appendingPathComponent(path.trimmingCharacters(in: ["/"])),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        PlexAuth.headers(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }  // unreachable / error
        let container = try? JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        return container?.mediaContainer.metadata ?? []
    }

    private func matchByTitle(_ items: [PlexMetadata], title: String, year: String?) -> PlexMetadata? {
        func norm(_ s: String) -> String {
            s.lowercased().filter { !$0.isWhitespace }
        }
        let target = norm(title)
        let yearInt = year.flatMap(Int.init)
        let exact = items.filter { norm($0.title ?? "") == target }
        if let yearInt, let hit = exact.first(where: { $0.year == yearInt }) { return hit }
        if let hit = exact.first { return hit }
        return items.first { norm($0.title ?? "").contains(target) || target.contains(norm($0.title ?? "")) }
    }

    // MARK: Deep link

    func deepLink(machineID: String, ratingKey: String) -> URL {
        let key = "/library/metadata/\(ratingKey)"
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ratingKey
        return URL(string: "https://app.plex.tv/desktop/#!/server/\(machineID)/details?key=\(key)")!
    }
}

/// Observable Plex connection state shared across the app.
@MainActor
final class PlexStore: ObservableObject {
    @Published private(set) var credential: PlexCredential?
    @Published private(set) var servers: [PlexServer] = []
    @Published var isConnecting = false
    @Published var errorMessage: String?

    private let service = PlexService()

    var isConnected: Bool { credential != nil }
    var username: String? { credential?.username }
    var serverCount: Int { servers.count }

    init() {
        if let data = Keychain.load(account: Keychain.plexAccount),
           let cred = try? JSONDecoder().decode(PlexCredential.self, from: data) {
            credential = cred
            Task { await refreshServers() }
        }
    }

    func connect() async {
        isConnecting = true
        errorMessage = nil
        do {
            let cred = try await PlexAuth().login()
            persist(cred)
            await refreshServers()
        } catch let error as PlexAuthError {
            if case .cancelled = error {} else { errorMessage = error.errorDescription }
        } catch {
            errorMessage = error.localizedDescription
        }
        isConnecting = false
    }

    func disconnect() {
        credential = nil
        servers = []
        Keychain.clear(account: Keychain.plexAccount)
    }

    func refreshServers() async {
        guard let token = credential?.authToken else { return }
        servers = await service.loadServers(token: token)
    }

    func findSource(ref: MediaRef, title: String, year: String?) async -> PlexMatch? {
        guard isConnected, !servers.isEmpty else { return nil }
        for server in servers {
            if let meta = await service.findMatch(server: server, ref: ref, title: title, year: year),
               let ratingKey = meta.ratingKey {
                return PlexMatch(
                    serverName: server.name,
                    resolution: meta.resolutionLabel,
                    deepLink: service.deepLink(machineID: server.machineIdentifier, ratingKey: ratingKey)
                )
            }
        }
        return nil
    }

    private func persist(_ cred: PlexCredential) {
        credential = cred
        if let data = try? JSONEncoder().encode(cred) {
            Keychain.save(data, account: Keychain.plexAccount)
        }
    }
}
