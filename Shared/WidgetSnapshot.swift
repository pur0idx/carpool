import Foundation
import WidgetKit

/// Everything the home-screen / CarPlay widget needs, written by the app into the shared
/// App Group folder. Widgets can't be updated live, so instead of "the current line" the app
/// hands over every line with the exact time it should appear, and iOS switches them on schedule.
struct WidgetSnapshot: Codable {
    struct Line: Codable {
        let time: Date      // when this line should start showing
        let text: String
    }

    var title: String
    var artist: String
    var isPlaying: Bool
    var artFile: String?
    var background: RGB
    var accent: RGB
    var lines: [Line]
    /// Shown instead of lyrics when there are none (e.g. "No lyrics found").
    var status: String?
    var songEnd: Date?
    var estimated: Bool
    /// When the app wrote this (used while paused: the clock is frozen at this moment).
    var writtenAt: Date = Date()
    /// Same lyrics layout setting as the Live Activity: "single", "next" or "three".
    var layout: String = "next"

    static let widgetKind = "LyricsWidget"

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
