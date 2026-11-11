import ActivityKit
import Foundation
import SwiftUI

/// Shared between the app (which starts/updates the Live Activity)
/// and the widget extension (which draws it on the lock screen, Dynamic Island and CarPlay).
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        struct Line: Codable, Hashable, Identifiable {
            var id: String      // stable per song + line, so SwiftUI can slide lines like a slot machine
            var text: String
        }

        /// A small window of lines around the current one (1 before, current, 2 after).
        var lines: [Line]
        var currentID: String?
        var trackTitle: String
        var artist: String
        var isPlaying: Bool
        /// Album cover file name inside the shared App Group folder.
        var artFile: String?
        var background: RGB
        var accent: RGB
        /// True when the timing is guessed (the song had no synced lyrics).
        var estimated: Bool = false
        /// Bumped on self-refresh so iOS treats a re-send as new content and redraws.
        var revision: Int = 0
        /// Lyrics layout (lock screen, CarPlay): "next" = current + next line (default);
        /// "three" = previous, current and next line; "single" = current line only, biggest.
        var carLayout: String = "next"
    }
}

/// A color that can travel inside the Live Activity state.
struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    static let defaultBackground = RGB(r: 0.08, g: 0.08, b: 0.09)
    static let defaultAccent = RGB(r: 0.12, g: 0.84, b: 0.38)   // Spotify-ish green
}
