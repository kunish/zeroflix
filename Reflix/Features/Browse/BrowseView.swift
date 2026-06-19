import SwiftUI

/// Genre / studio browse grid reached from the Discover cards.
struct BrowseView: View {
    let target: BrowseTarget

    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var items: [TMDBMedia] = []
    @State private var isLoading = true

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { media in
                    Button { router.open(media.ref) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            RemoteImage(path: media.posterPath ?? media.backdropPath, size: .w500, seed: media.displayTitle)
                                .aspectRatio(2.0 / 3.0, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(media.displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(RFX.text)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)

            if isLoading {
                ProgressView().tint(.white).padding(.top, 40)
            }
        }
        .rfxScroll()
        .background(RFX.bg.ignoresSafeArea())
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
            }
        }
        .tint(.white)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            switch target {
            case .genre(let g):
                items = try await TMDBService.shared.discover(type: .movie, genre: g.genreId)
            case .studio(let s):
                items = try await TMDBService.shared.discover(type: .tv, network: s.networkId)
            }
        } catch {
            items = []
        }
        isLoading = false
    }
}
