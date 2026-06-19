import SwiftUI

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var detail: TMDBDetail?
    @Published var isLoading = true
    @Published var error: String?

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
