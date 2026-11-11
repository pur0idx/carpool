import Foundation

/// What's playing right now, plus when we found out (to estimate the position between polls).
struct NowPlaying: Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval   // seconds
    let progress: TimeInterval   // seconds, at `fetchedAt`
    let isPlaying: Bool
    let fetchedAt: Date
    var artworkURL: URL? = nil

    /// Estimated playback position (seconds) at `date`.
    func position(at date: Date = Date()) -> TimeInterval {
        let elapsed = isPlaying ? date.timeIntervalSince(fetchedAt) : 0
        return min(progress + elapsed, duration)
    }
}

/// Reads the currently playing track from the Spotify Web API.
@MainActor
final class SpotifyClient {
    enum SpotifyError: LocalizedError {
        case rateLimited(TimeInterval)
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .rateLimited(let s): "Spotify rate limit, retrying in \(Int(s)) s"
            case .http(let code, let body): "Spotify error \(code): \(body)"
            }
        }
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable {
                struct Image: Decodable { let url: String; let width: Int? }
                let name: String
                let images: [Image]?
            }
            let id: String?
            let name: String
            let duration_ms: Double
            let artists: [Artist]?
            let album: Album?
        }
        let is_playing: Bool
        let progress_ms: Double?
        let currently_playing_type: String?
        let item: Item?
    }

    private let auth = SpotifyAuth.shared

    // MARK: - Playback control (needs Spotify Premium + the user-modify-playback-state scope)

    enum Command: String { case play, pause, next, previous }

    func send(_ command: Command) async throws {
        let (method, path): (String, String) = switch command {
        case .play: ("PUT", "play")
        case .pause: ("PUT", "pause")
        case .next: ("POST", "next")
        case .previous: ("POST", "previous")
        }
        let token = try await auth.accessToken()
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("0", forHTTPHeaderField: "Content-Length")
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw SpotifyError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// nil means nothing is playing (or it's not a song, e.g. a podcast or an ad).
    func currentlyPlaying() async throws -> NowPlaying? {
        try await currentlyPlaying(retrying: true)
    }

    private func currentlyPlaying(retrying: Bool) async throws -> NowPlaying? {
        let token = try await auth.accessToken()
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: req)
        let receivedAt = Date()
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200:
            break
        case 204:
            return nil
        case 401 where retrying:
            _ = try await auth.accessToken(forceRefresh: true)
            return try await currentlyPlaying(retrying: false)
        case 429:
            let wait = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10
            throw SpotifyError.rateLimited(wait)
        case let code:
            throw SpotifyError.http(code, String(data: data, encoding: .utf8) ?? "")
        }

        let r = try JSONDecoder().decode(Response.self, from: data)
        guard r.currently_playing_type == "track", let item = r.item else { return nil }
        // Spotify gives ~640, 300 and 64 px covers; the 640 one looks best in the app.
        let cover = item.album?.images?.max { ($0.width ?? 0) < ($1.width ?? 0) }
        return NowPlaying(
            id: item.id ?? "\(item.name)-\(item.duration_ms)",
            title: item.name,
            artist: item.artists?.map(\.name).joined(separator: ", ") ?? "",
            album: item.album?.name ?? "",
            duration: item.duration_ms / 1000,
            progress: (r.progress_ms ?? 0) / 1000,
            isPlaying: r.is_playing,
            fetchedAt: receivedAt,
            artworkURL: cover.flatMap { URL(string: $0.url) }
        )
    }
}
