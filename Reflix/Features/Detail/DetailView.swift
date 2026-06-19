import SwiftUI

struct DetailView: View {
    let ref: MediaRef

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DetailViewModel

    init(ref: MediaRef) {
        self.ref = ref
        _model = StateObject(wrappedValue: DetailViewModel(ref: ref))
    }

    var body: some View {
        ZStack(alignment: .top) {
            RFX.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    sourceCard
                    actionChips
                    overviewBlock
                    similarSection
                    stillsSection
                    castSection
                    Color.clear.frame(height: 30)
                }
            }
            .rfxScroll()
            .ignoresSafeArea(edges: .top)

            topBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(path: model.detail?.backdropPath ?? model.detail?.posterPath,
                        size: .original, seed: model.detail?.displayTitle ?? "\(ref.id)")
                .frame(height: 640)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.3), location: 0),
                    .init(color: .black.opacity(0.05), location: 0.3),
                    .init(color: RFX.bg, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 0) {
                Text(model.detail?.displayTitle ?? "")
                    .font(.system(size: 44, weight: .black))
                    .kerning(2)
                    .foregroundStyle(RFX.accent)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.6), radius: 16, y: 2)

                if let detail = model.detail {
                    Text(detail.metaLine(type: ref.type))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xd8d8da))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 1)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
        }
        .frame(height: 640)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            circleButton("chevron.left") { dismiss() }
            Spacer()
            HStack(spacing: 12) {
                let saved = library.contains(ref: ref, in: .watchLater)
                circleButton(saved ? "bookmark.fill" : "bookmark", tint: saved ? RFX.accent : nil) {
                    Task { if let s = model.snapshot() { await library.toggle(s, in: .watchLater) } }
                }
                circleButton("square.and.arrow.up") { }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func circleButton(_ systemName: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint ?? .white)
                .frame(width: 38, height: 38)
                .glassCircle()
        }
        .buttonStyle(.plain)
    }

    // MARK: Source card (faithful "没有找到可用资源")

    private var sourceCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "nosign").font(.system(size: 17)).opacity(0.7)
            Text("没有找到可用资源")
                .font(.system(size: 18, weight: .bold))
        }
        .foregroundStyle(Color(hex: 0xe6e6e8))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassRoundedRect(18)
        .padding(.horizontal, 22)
        .padding(.top, 4)
    }

    // MARK: Action chips (collect to library)

    private var actionChips: some View {
        HStack(spacing: 10) {
            chip(.favorite, icon: "heart", label: "收藏")
            chip(.watching, icon: "play.circle", label: "正在观看")
            chip(.history, icon: "checkmark.circle", label: "看过")
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private func chip(_ list: LibraryList, icon: String, label: String) -> some View {
        let active = library.contains(ref: ref, in: list)
        return Button {
            Task { if let s = model.snapshot() { await library.toggle(s, in: list) } }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: active ? icon + ".fill" : icon).font(.system(size: 14))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(active ? .black : RFX.text2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(RFX.card), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Overview

    @ViewBuilder private var overviewBlock: some View {
        if let overview = model.detail?.overview, !overview.isEmpty {
            Text(overview)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: 0xe2e2e4))
                .lineSpacing(5)
                .padding(22)
        } else if model.isLoading {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(RFX.card).frame(height: 14)
                }
            }
            .padding(22)
            .redacted(reason: .placeholder)
        }
    }

    // MARK: Similar

    @ViewBuilder private var similarSection: some View {
        if let similar = model.detail?.similar?.results, !similar.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "更多类似")
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(similar) { media in
                            WideMediaCard(media: media, showsDescription: false) { router.open(media.ref) }
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .rfxScroll()
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: Stills

    @ViewBuilder private var stillsSection: some View {
        if let stills = model.detail?.images?.backdrops, !stills.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "剧照")
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(Array(stills.prefix(10).enumerated()), id: \.offset) { _, image in
                            RemoteImage(path: image.filePath, size: .w780, seed: image.filePath)
                                .frame(width: 300, height: 170)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 6)
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .rfxScroll()
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: Cast

    @ViewBuilder private var castSection: some View {
        if let cast = model.detail?.credits?.cast, !cast.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "演职人员")
                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(cast.prefix(15)) { member in
                            VStack(spacing: 8) {
                                RemoteAvatar(path: member.profilePath, size: 88, seed: member.name)
                                Text(member.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(RFX.text)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 88)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .rfxScroll()
            }
        }
    }
}
