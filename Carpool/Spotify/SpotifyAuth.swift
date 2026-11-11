import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

/// Spotify login using "Authorization Code with PKCE", which needs no client secret,
/// so it's safe to do entirely inside the app.
@MainActor
@Observable
final class SpotifyAuth {
    static let shared = SpotifyAuth()

    static let redirectURI = "lyricscar://callback"
    static let callbackScheme = "lyricscar"
    // user-modify-playback-state: play/pause/skip from the widget (needs Spotify Premium).
    private static let scopes = "user-read-currently-playing user-read-playback-state user-modify-playback-state"

    enum AuthError: LocalizedError {
        case noClientID, cancelled, badResponse(String), notLoggedIn
        var errorDescription: String? {
            switch self {
            case .noClientID: "Paste your Spotify Client ID in Settings first."
            case .cancelled: "Login was cancelled."
            case .badResponse(let s): "Spotify login failed: \(s)"
            case .notLoggedIn: "Not connected to Spotify."
            }
        }
    }

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var scope: String? = nil
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
        let scope: String?
    }

    /// Client ID from your app at developer.spotify.com/dashboard.
    var clientID: String {
        didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spotifyClientID") }
    }
    private(set) var isLoggedIn = false

    private var tokens: Tokens? {
        didSet {
            isLoggedIn = tokens != nil
            if let tokens, let data = try? JSONEncoder().encode(tokens) {
                Keychain.set(data, for: "spotifyTokens")
            } else {
                Keychain.delete("spotifyTokens")
            }
        }
    }

    private var session: ASWebAuthenticationSession?
    private let anchor = PresentationAnchor()
    private var refreshTask: Task<String, Error>?

    private init() {
        clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
        if let data = Keychain.get("spotifyTokens"), let saved = try? JSONDecoder().decode(Tokens.self, from: data) {
            tokens = saved
            isLoggedIn = true
        }
    }

    // MARK: - Login / logout

    func login() async throws {
        guard !clientID.isEmpty else { throw AuthError.noClientID }

        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: Self.scopes),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: Self.callbackScheme) { url, error in
                if let url {
                    cont.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    cont.resume(throwing: AuthError.cancelled)
                } else {
                    cont.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            s.presentationContextProvider = anchor
            session = s
            s.start()
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value { throw AuthError.badResponse(err) }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.badResponse("no code returned")
        }

        let response = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        guard let refresh = response.refresh_token else { throw AuthError.badResponse("no refresh token") }
        tokens = Tokens(accessToken: response.access_token,
                        refreshToken: refresh,
                        expiresAt: Date().addingTimeInterval(response.expires_in),
                        scope: response.scope)
        log("Spotify connected. Permissions granted: \(response.scope ?? "(Spotify didn't say)")")
    }

    /// False if you connected before playback controls were added: reconnect once to enable them.
    var canControlPlayback: Bool {
        tokens?.scope?.contains("user-modify-playback-state") == true
    }

    func logout() {
        tokens = nil
    }

    // MARK: - Tokens

    /// Returns a usable access token, refreshing it if it's about to expire.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let t = tokens else { throw AuthError.notLoggedIn }
        if !forceRefresh, t.expiresAt > Date().addingTimeInterval(60) { return t.accessToken }

        if let refreshTask { return try await refreshTask.value }
        let task = Task<String, Error> {
            defer { refreshTask = nil }
            let r = try await tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": t.refreshToken,
                "client_id": clientID,
            ])
            tokens = Tokens(accessToken: r.access_token,
                            refreshToken: r.refresh_token ?? t.refreshToken,
                            expiresAt: Date().addingTimeInterval(r.expires_in),
                            scope: r.scope ?? t.scope)
            return r.access_token
        }
        refreshTask = task
        return try await task.value
    }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = c.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 400 || status == 401, form["grant_type"] == "refresh_token" {
                tokens = nil   // refresh token revoked: make the user log in again
            }
            throw AuthError.badResponse(String(data: data, encoding: .utf8) ?? "HTTP \(status)")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - PKCE helpers

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Tells the login sheet which window to appear over.
private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
            return ASPresentationAnchor(windowScene: scenes[0])
        }
    }
}
