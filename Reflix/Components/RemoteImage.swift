import SwiftUI

/// AsyncImage with a deterministic gradient placeholder + crossfade, matching
/// the source design's gradient-while-loading behaviour.
struct RemoteImage: View {
    let path: String?
    let size: TMDBImageSize
    let seed: String

    init(path: String?, size: TMDBImageSize, seed: String = "") {
        self.path = path
        self.size = size
        self.seed = seed.isEmpty ? (path ?? "rfx") : seed
    }

    var body: some View {
        let gradient = PlaceholderGradient.make(seed: PlaceholderGradient.seed(for: seed))
        AsyncImage(url: tmdbImageURL(path, size), transaction: .init(animation: .easeOut(duration: 0.35))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty, .failure:
                gradient
            @unknown default:
                gradient
            }
        }
    }
}

/// Circular avatar variant (people / cast).
struct RemoteAvatar: View {
    let path: String?
    let size: CGFloat
    let seed: String

    var body: some View {
        RemoteImage(path: path, size: .w342, seed: seed)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
    }
}
