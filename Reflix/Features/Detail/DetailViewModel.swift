import SwiftUI

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var detail: TMDBDetail?
    @Published var isLoading = true
    @Published var error: String?

    @Published var plexMatch: PlexMatch?
    @Published var isCheckingPlex = false
    private var plexChecked = false

    let ref: MediaRef
    init(ref: MediaRef) { self.ref = ref }

    func load() async {
        isLoading = true
        error = nil
        do {
            detail = try await TMDBService.shared.detail(ref)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "加载详情失败"
        }
        isLoading = false
    }

    /// Looks the title up in the user's connected Plex libraries (once).
    func loadPlexSource(_ store: PlexStore) async {
        guard store.isConnected, let detail, !plexChecked else { return }
        plexChecked = true
        isCheckingPlex = true
        plexMatch = await store.findSource(ref: ref, title: detail.displayTitle, year: detail.year)
        isCheckingPlex = false
    }

    /// A snapshot that can be persisted to the user's library.
    func snapshot() -> MediaSnapshot? {
        guard let detail else { return nil }
        return MediaSnapshot(
            tmdbId: detail.id,
            mediaType: ref.type,
            titleText: detail.displayTitle,
            poster: detail.posterPath,
            backdrop: detail.backdropPath,
            overviewText: detail.overview,
            runtime: detail.runtimeMinutes
        )
    }
}

/// Concrete `DetailLike` used when saving a detail page to the library.
struct MediaSnapshot: DetailLike {
    let tmdbId: Int
    let mediaType: MediaType
    let titleText: String?
    let poster: String?
    let backdrop: String?
    let overviewText: String?
    let runtime: Int?
}
