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
