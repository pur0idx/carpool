import AppIntents
import Foundation

extension Notification.Name {
    static let refreshLyricsRequested = Notification.Name("refreshLyricsRequested")
}

/// The ↻ button on the Live Activity. Being a LiveActivityIntent, iOS runs it inside
/// the app's process (not the widget's), where LyricsEngine listens for the notification.
struct RefreshLyricsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh Lyrics"
    static let description = IntentDescription("Re-checks the song playing on Spotify and reloads its lyrics.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .refreshLyricsRequested, object: nil)
        }
        return .result()
    }
}
