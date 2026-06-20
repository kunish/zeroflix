import SwiftUI

/// Auth gate: show the email login flow until a Supabase session exists.
struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ZStack {
            RFX.bgRoot.ignoresSafeArea()
            if auth.isAuthenticated {
                MainShell()
                    .transition(.opacity)
            } else {
                AuthView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.isAuthenticated)
        // Sign-out / account-switch: drop the previous user's in-memory library
        // so it can't linger for the next account (disk is already per-user keyed).
        .onChange(of: auth.session?.userId) { _, _ in
            library.reset()
        }
        .task { await debugAutoLoginIfNeeded() }
    }

    /// DEBUG-only convenience for UI verification. Launch env vars:
    ///   REFLIX_AUTOLOGIN_EMAIL / REFLIX_AUTOLOGIN_PASSWORD  → sign in
    ///   REFLIX_START_TAB=mine                                → open Mine tab
    ///   REFLIX_OPEN_DETAIL=tv:1399 (or movie:123)            → push a detail
    /// Compiled out of release builds.
    private func debugAutoLoginIfNeeded() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if !auth.isAuthenticated,
           let email = env["REFLIX_AUTOLOGIN_EMAIL"],
           let password = env["REFLIX_AUTOLOGIN_PASSWORD"] {
            await auth.signUp(email: email, password: password)
        }
        guard auth.isAuthenticated else { return }

        if env["REFLIX_SEED_LIBRARY"] == "1" {
            let movies = (try? await TMDBService.shared.trending(.movie)) ?? []
            let shows = (try? await TMDBService.shared.trending(.tv)) ?? []
            if let s = shows.first { await library.add(s, to: .watching) }
            if let m = movies.first { await library.add(m, to: .watchLater) }
            if shows.count > 1 { await library.add(shows[1], to: .history) }
        }

        if env["REFLIX_START_TAB"] == "mine" { router.tab = .mine }

        if env["REFLIX_OPEN_SETTINGS"] == "1" {
            try? await Task.sleep(nanoseconds: 900_000_000)
            router.showSettings = true
        }

        if env["REFLIX_OPEN_BROWSE"] == "genre" {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            router.browse(.genre(GenreCard(name: "剧情 Drama", genreId: 18, colors: [0x3a4a6e, 0x1a2238])))
        }

        if let deepLink = env["REFLIX_OPEN_DETAIL"] {
            let parts = deepLink.split(separator: ":")
            if parts.count == 2, let id = Int(parts[1]),
               let type = MediaType(rawValue: String(parts[0])) {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                router.open(MediaRef(id: id, type: type))
            }
        }
        #endif
    }
}
