import Foundation

/// Result of a lyrics lookup.
enum LyricsResult: Sendable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case notFound
}

/// Talks to LRCLIB (https://lrclib.net), a free, open database of time-synced lyrics.
struct LRCLIBClient: Sendable {
    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private let base = URL(string: "https://lrclib.net/api")!

    /// Looks up lyrics. `duration` (seconds) helps pick the right version of a song.
    func lyrics(title: String, artist: String, album: String?, duration: Double?) async throws -> LyricsResult {
        // 1) Exact lookup.
        if let duration, let album, !album.isEmpty,
           let record = try await get(title: title, artist: artist, album: album, duration: duration),
           let result = convert(record) {
            return result
        }

        // 2) Search with the original title, then with a cleaned-up one
        //    ("Song - Remastered 2011" -> "Song", "Song (feat. X)" -> "Song").
        var titles = [title]
        let cleaned = Self.clean(title)
        if cleaned != title { titles.append(cleaned) }

        var plainFallback: LyricsResult?
        for t in titles {
            let records = try await search(title: t, artist: artist)
            if let best = pick(records, duration: duration, needSynced: true), let r = convert(best) {
                return r
            }
            if plainFallback == nil, let best = pick(records, duration: duration, needSynced: false) {
                plainFallback = convert(best)
            }
        }
        return plainFallback ?? .notFound
    }

    // MARK: - Requests

    private func get(title: String, artist: String, album: String, duration: Double) async throws -> Record? {
        var c = URLComponents(url: base.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: album),
            .init(name: "duration", value: String(Int(duration.rounded()))),
        ]
        let (data, response) = try await URLSession.shared.data(for: request(c.url!))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private func search(title: String, artist: String) async throws -> [Record] {
        var c = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
        ]
        let (data, response) = try await URLSession.shared.data(for: request(c.url!))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = 15
        // LRCLIB asks clients to identify themselves.
        r.setValue("Carpool/1.0 (personal iOS app)", forHTTPHeaderField: "User-Agent")
        return r
    }

    // MARK: - Helpers

    private func pick(_ records: [Record], duration: Double?, needSynced: Bool) -> Record? {
        let candidates = records.filter { r in
            if needSynced { return !(r.syncedLyrics ?? "").isEmpty }
            return !(r.plainLyrics ?? "").isEmpty || r.instrumental == true
        }
        guard let duration else { return candidates.first }
        // Prefer the version whose length is closest to the playing track (within 5 s).
        return candidates
            .filter { abs(($0.duration ?? duration) - duration) <= 5 }
            .min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
    }

    private func convert(_ r: Record) -> LyricsResult? {
        if let synced = r.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if r.instrumental == true { return .instrumental }
        if let plain = r.plainLyrics, !plain.isEmpty { return .plain(plain) }
        return nil
    }

    static func clean(_ title: String) -> String {
        var t = title
        if let dash = t.range(of: " - ") { t = String(t[..<dash.lowerBound]) }
        t = t.replacingOccurrences(of: #"\s*[\(\[](feat\.?|ft\.?|with|from)[^\)\]]*[\)\]]"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespaces)
    }
}
