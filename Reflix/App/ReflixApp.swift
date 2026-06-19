import SwiftUI

@main
struct ReflixApp: App {
    @StateObject private var auth: AuthStore
    @StateObject private var library: LibraryStore
    @StateObject private var router = Router()
    @StateObject private var plex = PlexStore()

    init() {
        let auth = AuthStore()
        _auth = StateObject(wrappedValue: auth)
        _library = StateObject(wrappedValue: LibraryStore(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(library)
                .environmentObject(router)
                .environmentObject(plex)
                .preferredColorScheme(.dark)
                .tint(RFX.accent)
        }
    }
}
