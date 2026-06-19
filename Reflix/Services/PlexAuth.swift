import AuthenticationServices
import UIKit

enum PlexAuthError: LocalizedError {
    case cancelled
    case timedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "已取消 Plex 登录"
        case .timedOut: return "Plex 授权超时，请重试"
        case .server(let m): return m
        }
    }
}

/// Drives Plex's PIN-based OAuth: create a PIN, let the user authorise in a
/// web session, then poll until an auth token is issued.
@MainActor
final class PlexAuth: NSObject, ASWebAuthenticationPresentationContextProviding {

    private let session = URLSession(configuration: .default)
    private var webSession: ASWebAuthenticationSession?

    /// Headers identifying this client to plex.tv.
    nonisolated static func headers(token: String? = nil) -> [String: String] {
        var h = [
            "X-Plex-Product": AppConfig.plexProduct,
            "X-Plex-Version": AppConfig.plexVersion,
            "X-Plex-Client-Identifier": KeyStore.plexClientID,
            "X-Plex-Platform": "iOS",
            "X-Plex-Device": "iPhone",
            "X-Plex-Device-Name": "Reflix",
            "Accept": "application/json",
        ]
        if let token { h["X-Plex-Token"] = token }
        return h
    }

    /// Runs the full login flow and returns a stored credential.
    func login() async throws -> PlexCredential {
        let pin = try await createPin()
        let authURL = buildAuthURL(code: pin.code)

        // Present the web auth session. It resolves on the forwardUrl callback
        // OR when the user dismisses it — either way we then poll for the token.
        await presentWebSession(url: authURL)

        let token = try await pollForToken(pinID: pin.id, code: pin.code)
        let account = (try? await fetchAccount(token: token))
        let username = account?.displayName ?? "Plex"
        return PlexCredential(authToken: token, username: username, clientID: KeyStore.plexClientID)
    }

    // MARK: Steps

    private func createPin() async throws -> PlexPin {
        var req = URLRequest(url: URL(string: AppConfig.plexPinsURL + "?strong=true")!)
        req.httpMethod = "POST"
        Self.headers().forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: req)
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            throw PlexAuthError.server("无法创建 Plex 授权请求")
        }
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }

    private func buildAuthURL(code: String) -> URL {
        var items = [
            URLQueryItem(name: "clientID", value: KeyStore.plexClientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "forwardUrl", value: AppConfig.plexForwardURL),
            URLQueryItem(name: "context[device][product]", value: AppConfig.plexProduct),
        ]
        var comps = URLComponents()
        comps.queryItems = items
        let query = comps.percentEncodedQuery ?? ""
        // Plex reads parameters from the URL fragment.
        return URL(string: AppConfig.plexAuthAppURL + "#?" + query)!
    }

    private func presentWebSession(url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let webSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.plexCallbackScheme
            ) { _, _ in
                continuation.resume()
            }
            webSession.presentationContextProvider = self
            webSession.prefersEphemeralWebBrowserSession = false
            self.webSession = webSession
            if !webSession.start() {
                continuation.resume()
            }
        }
        self.webSession = nil
    }

    private func pollForToken(pinID: Int, code: String) async throws -> String {
        let url = URL(string: "\(AppConfig.plexPinsURL)/\(pinID)?code=\(code)")!
        for _ in 0..<20 {
            var req = URLRequest(url: url)
            Self.headers().forEach { req.setValue($1, forHTTPHeaderField: $0) }
            if let (data, _) = try? await session.data(for: req),
               let pin = try? JSONDecoder().decode(PlexPin.self, from: data),
               let token = pin.authToken, !token.isEmpty {
                return token
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw PlexAuthError.cancelled
    }

    private func fetchAccount(token: String) async throws -> PlexAccount {
        var req = URLRequest(url: URL(string: AppConfig.plexUserURL)!)
        Self.headers(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(PlexAccount.self, from: data)
    }

    // MARK: ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
