import AppIntents
import Foundation

extension Notification.Name {
    static let playbackCommand = Notification.Name("playbackCommand")
}

/// Play/pause and skip buttons on the widget. As AudioPlaybackIntents, iOS runs them inside
/// the app's process (launching it in the background if needed), where LyricsEngine listens
/// for the notification and tells Spotify.
struct TogglePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause Spotify"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .playbackCommand, object: "toggle")
        }
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Song on Spotify"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .playbackCommand, object: "next")
        }
        return .result()
    }
}
