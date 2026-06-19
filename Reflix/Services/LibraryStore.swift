import Foundation
import SwiftUI

/// The five library buckets surfaced on the "我的" tab.
enum LibraryList: String, CaseIterable, Identifiable {
    case watching       // 正在观看
    case upcoming       // 即将更新
    case watchLater     // 稍后观看
    case history        // 观看历史
    case favorite       // 收藏

    var id: String { rawValue }

    /// Maps to the `list_type` check constraint in Postgres.
    var apiValue: String {
        switch self {
        case .watching: return "watching"
        case .upcoming: return "upcoming"
        case .watchLater: return "watch_later"
        case .history: return "history"
        case .favorite: return "favorite"
        }
    }

    var title: String {
        switch self {
        case .watching: return "正在观看"
        case .upcoming: return "即将更新"
        case .watchLater: return "稍后观看"
        case .history: return "观看历史"
        case .favorite: return "收藏"
        }
    }
}

struct LibraryItem: Codable, Identifiable, Hashable {
    var id: String?
    var tmdbId: Int
    var mediaType: String
    var listType: String
    var title: String?
    var posterPath: String?
    var backdropPath: String?
    var overview: String?
    var season: Int?
    var episode: Int?
    var progressMinutes: Int?
    var runtimeMinutes: Int?
    var addedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case listType = "list_type"
        case title
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case overview
        case season
        case episode
        case progressMinutes = "progress_minutes"
        case runtimeMinutes = "runtime_minutes"
        case addedAt = "added_at"
    }

    var ref: MediaRef {
        MediaRef(id: tmdbId, type: MediaType(rawValue: mediaType) ?? .movie)
    }
}

/// PostgREST-backed repository + observable cache for the signed-in user's library.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var itemsByList: [String: [LibraryItem]] = [:]
    @Published var isLoading = false

    private unowned let auth: AuthStore
    private let net = URLSession(configuration: .default)

    init(auth: AuthStore) { self.auth = auth }

    func items(for list: LibraryList) -> [LibraryItem] {
        itemsByList[list.apiValue] ?? []
    }

    func contains(ref: MediaRef, in list: LibraryList) -> Bool {
        items(for: list).contains { $0.tmdbId == ref.id && $0.mediaType == ref.type.rawValue }
    }

    // MARK: Reads

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        guard let token = await auth.validAccessToken() else { return }
        do {
            var req = restRequest(path: "/library_items?select=*&order=updated_at.desc", token: token)
            req.httpMethod = "GET"
            let (data, response) = try await net.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let rows = try JSONDecoder().decode([LibraryItem].self, from: data)
            var grouped: [String: [LibraryItem]] = [:]
            for row in rows { grouped[row.listType, default: []].append(row) }
            itemsByList = grouped
        } catch {
            // Keep whatever is cached on a transient failure.
        }
    }

    // MARK: Writes

    func add(_ media: DetailLike, to list: LibraryList) async {
        guard let token = await auth.validAccessToken() else { return }
        var body: [String: Any] = [
            "tmdb_id": media.tmdbId,
            "media_type": media.mediaType.rawValue,
            "list_type": list.apiValue,
        ]
        if let title = media.titleText { body["title"] = title }
        if let poster = media.poster { body["poster_path"] = poster }
        if let backdrop = media.backdrop { body["backdrop_path"] = backdrop }
        if let overview = media.overviewText { body["overview"] = overview }
        if let runtime = media.runtime { body["runtime_minutes"] = runtime }
        do {
            var req = restRequest(
                path: "/library_items?on_conflict=user_id,tmdb_id,media_type,list_type",
                token: token)
            req.httpMethod = "POST"
            req.setValue("resolution=merge-duplicates,return=representation",
                         forHTTPHeaderField: "Prefer")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            _ = try await net.data(for: req)
            await loadAll()
        } catch { }
    }

    func remove(ref: MediaRef, from list: LibraryList) async {
        guard let token = await auth.validAccessToken() else { return }
        let path = "/library_items?tmdb_id=eq.\(ref.id)&media_type=eq.\(ref.type.rawValue)&list_type=eq.\(list.apiValue)"
        var req = restRequest(path: path, token: token)
        req.httpMethod = "DELETE"
        _ = try? await net.data(for: req)
        await loadAll()
    }

    func toggle(_ media: DetailLike, in list: LibraryList) async {
        if contains(ref: media.ref, in: list) {
            await remove(ref: media.ref, from: list)
        } else {
            await add(media, to: list)
        }
    }

    // MARK: Request builder

    private func restRequest(path: String, token: String) -> URLRequest {
        var req = URLRequest(url: URL(string: AppConfig.supabaseRestURL + path)!)
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }
}

/// Anything that can be saved to the library (a TMDB detail or a media row).
protocol DetailLike {
    var tmdbId: Int { get }
    var mediaType: MediaType { get }
    var titleText: String? { get }
    var poster: String? { get }
    var backdrop: String? { get }
    var overviewText: String? { get }
    var runtime: Int? { get }
}

extension DetailLike {
    var ref: MediaRef { MediaRef(id: tmdbId, type: mediaType) }
}

extension TMDBMedia: DetailLike {
    var tmdbId: Int { id }
    var mediaType: MediaType { resolvedType }
    var titleText: String? { displayTitle }
    var poster: String? { posterPath }
    var backdrop: String? { backdropPath }
    var overviewText: String? { overview }
    var runtime: Int? { nil }
}
