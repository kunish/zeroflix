import SwiftUI

/// AsyncImage with a deterministic gradient placeholder + crossfade, matching
/// the source design's gradient-while-loading behaviour.
///
/// The image is rendered as an overlay on a size-neutral `Color.clear` base so
/// it fills whatever frame the call site gives it (e.g. `.frame(height: 640)`)
/// WITHOUT leaking the image's intrinsic aspect-ratio width into layout — that
/// would otherwise blow up the enclosing VStack far wider than the screen.
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
        Color.clear
            .overlay {
                AsyncImage(
                    url: tmdbImageURL(path, size),
                    transaction: .init(animation: .easeOut(duration: 0.35))
                ) { phase in
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
            .clipped()
            // Make the (otherwise Color.clear-backed) image region hit-testable
            // so Buttons that use it as their content respond to taps.
            .contentShape(Rectangle())
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
